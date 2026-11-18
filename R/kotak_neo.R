# Optional live feed for NSE stocks from the Kotak Neo Trade API (v2 REST, free for
# Kotak Neo customers). Used only for the live pages: like the Yahoo feed it never enters
# the research datasets. Read-only: this module calls login, scrip master, quotes and
# historical candles; it has no order functions.
#
# Credentials are read from environment variables, normally set in a git-ignored
# .Renviron file in the project root (see docs/operations/KOTAK_NEO.md):
#   KOTAK_ACCESS_TOKEN  token from Neo app/web -> More -> Trade API -> your application
#   KOTAK_MOBILE        registered mobile number with country code, e.g. +91XXXXXXXXXX
#   KOTAK_UCC           client code
#   KOTAK_MPIN          6-digit MPIN
#   KOTAK_TOTP_SECRET   base32 secret of the authenticator registration (optional: lets the
#                       API sign in by itself; otherwise run_api.R asks for the 6-digit code)
# When they are missing, nothing here runs and the live feed stays on Yahoo.
# API reference: https://github.com/Kotak-Neo/Kotak-Neo/tree/main/docs

KOTAK <- list(
  login_url = "https://mis.kotaksecurities.com/login/1.0/tradeApiLogin",
  validate_url = "https://mis.kotaksecurities.com/login/1.0/tradeApiValidate",
  fin_key = "neotradeapi",
  scrip_cache = file.path("data", "live", "kotak_nse_cm.csv"),
  session_hours = 8
)
KOTAK_STATE <- new.env()

kotak_env <- function(k) Sys.getenv(paste0("KOTAK_", k), "")
kotak_configured <- function() all(nzchar(vapply(c("ACCESS_TOKEN", "MOBILE", "UCC", "MPIN"), kotak_env, "")))

# ---- TOTP (RFC 6238, HMAC-SHA1, 30 s, 6 digits) ----
base32_decode <- function(s) {
  s <- toupper(gsub("[^A-Za-z2-7]", "", s))
  v <- match(strsplit(s, "")[[1]], c(LETTERS, 2:7)) - 1
  bits <- as.vector(vapply(v, function(x) as.integer(intToBits(x))[5:1], integer(5)))
  bits <- bits[seq_len(length(bits) - length(bits) %% 8)]
  as.raw(colSums(matrix(bits, 8) * 2^(7:0)))
}
hmac_sha1 <- function(key, msg) {
  if (requireNamespace("openssl", quietly = TRUE)) return(as.raw(openssl::sha1(msg, key = key)))
  if (requireNamespace("digest", quietly = TRUE)) return(digest::hmac(key, msg, "sha1", raw = TRUE))
  stop("TOTP needs the 'openssl' or 'digest' R package")
}
totp <- function(secret, time = Sys.time(), step = 30, digits = 6, key = base32_decode(secret)) {
  ctr <- floor(as.numeric(time) / step)
  msg <- as.raw(vapply(7:0, function(i) (ctr %/% 256^i) %% 256, 0))
  h <- as.integer(hmac_sha1(key, msg))
  o <- bitwAnd(h[20], 15L)
  code <- (bitwAnd(h[o + 1], 127L) * 2^24 + h[o + 2] * 2^16 + h[o + 3] * 2^8 + h[o + 4]) %% 10^digits
  formatC(code, width = digits, flag = "0", format = "d")
}

# ---- HTTP ----
kotak_http <- function(url, headers, body = NULL, timeout = 20) {
  h <- curl::new_handle(timeout = timeout)
  curl::handle_setheaders(h, .list = as.list(headers))
  if (!is.null(body)) curl::handle_setopt(h, customrequest = "POST",
                                          postfields = jsonlite::toJSON(body, auto_unbox = TRUE))
  r <- curl::curl_fetch_memory(url, handle = h)
  txt <- rawToChar(r$content)
  j <- tryCatch(jsonlite::fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)
  if (r$status_code != 200 || identical(toupper(j$status %||% ""), "ERROR")) {
    msg <- j$message %||% j$fault$message %||% j$data$message %||% substr(txt, 1, 160)
    stop(sprintf("Kotak Neo HTTP %d: %s", r$status_code, msg), call. = FALSE)
  }
  j
}

# Two-step login (TOTP, then MPIN). The access token, MPIN and TOTP never leave this function
# except in the request headers/body to Kotak; nothing is logged.
kotak_login <- function(code = NULL) {
  tok <- kotak_env("ACCESS_TOKEN")
  if (is.null(code)) {
    sec <- kotak_env("TOTP_SECRET")
    code <- if (nzchar(sec)) totp(sec) else kotak_env("TOTP")
  }
  if (!nzchar(code)) stop("Kotak Neo: no TOTP code (set KOTAK_TOTP_SECRET or enter the code at start-up)")
  hd <- c(Authorization = tok, `neo-fin-key` = KOTAK$fin_key, `Content-Type` = "application/json")
  v <- kotak_http(KOTAK$login_url, hd, list(mobileNumber = kotak_env("MOBILE"), ucc = kotak_env("UCC"), totp = code))$data
  t <- kotak_http(KOTAK$validate_url, c(hd, sid = v$sid, Auth = v$token), list(mpin = kotak_env("MPIN")))$data
  if (is.null(t$baseUrl)) stop("Kotak Neo: login answered without baseUrl")
  s <- list(base_url = sub("/$", "", t$baseUrl), token = t$token, sid = t$sid, at = as.numeric(Sys.time()))
  KOTAK_STATE$session <- s
  s
}

kotak_session <- function(max_age = KOTAK$session_hours * 3600) {
  s <- KOTAK_STATE$session
  if (!is.null(s) && as.numeric(Sys.time()) - s$at < max_age) return(s)
  if (nzchar(kotak_env("TOTP_SECRET"))) return(kotak_login())
  stop("Kotak Neo session expired; restart the API to sign in again")
}
kotak_get <- function(path, s = kotak_session())
  kotak_http(paste0(s$base_url, path), c(Authorization = kotak_env("ACCESS_TOKEN"), `Content-Type` = "application/json"))

# ---- instruments: Yahoo "RELIANCE.NS" -> Kotak NSE cash token (scrip master, cached daily) ----
kotak_scrip_map <- function(refresh = FALSE, path = KOTAK$scrip_cache) {
  if (!refresh && file.exists(path) && difftime(Sys.time(), file.mtime(path), units = "hours") < 20)
    return(utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character"))
  fp <- unlist(kotak_get("/script-details/1.0/masterscrip/file-paths")$data$filesPaths)
  u <- fp[grepl("nse_cm", fp)][1]
  if (is.na(u)) stop("Kotak Neo: no nse_cm scrip master in file-paths")
  m <- utils::read.csv(u, stringsAsFactors = FALSE, colClasses = "character", check.names = FALSE)
  names(m) <- sub(";$", "", trimws(names(m)))
  m <- m[grepl("-EQ$", m$pTrdSymbol), c("pSymbol", "pTrdSymbol", "pExchSeg")]
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(m, path, row.names = FALSE)
  m
}
kotak_token_of <- function(symbols, map = kotak_scrip_map()) {
  trd <- paste0(sub("\\.NS$", "", symbols), "-EQ")
  stats::setNames(map$pSymbol[match(trd, map$pTrdSymbol)], symbols)
}

# ---- market data ----
parse_kotak_candles <- function(j, symbol) {
  rows <- j$data$candles
  if (!length(rows)) return(NULL)
  num <- function(k) vapply(rows, function(r) as.numeric(r[[k]] %||% NA), 0)
  ts <- vapply(rows, function(r) as.character(r[[1]]), "")
  d <- data.frame(ticker = symbol, ts = as.POSIXct(ts, format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC"),
                  open = num(2), high = num(3), low = num(4), close = num(5), volume = num(6))
  d[is.finite(d$close) & is.finite(d$open) & !is.na(d$ts), ]
}

parse_kotak_quotes <- function(j, tokens) {
  # j: list of quote objects; ohlc$close is the previous session's close (ltp - change).
  out <- list()
  for (q in j) {
    tk <- names(tokens)[match(as.character(q$exchange_token), tokens)]
    if (is.na(tk)) next
    out[[tk]] <- list(prev_close = as.numeric(q$ohlc$close %||% NA), price = as.numeric(q$ltp %||% NA),
                      volume = NA_real_, market_time = as.POSIXct(as.numeric(q$lstup_time %||% NA), origin = "1970-01-01", tz = "UTC"))
  }
  out
}

# Same contract as fetch_intraday_many(): list(data = per-symbol bars with attr "meta", errors).
kotak_intraday_many <- function(symbols, interval = "1m", range = "1d") {
  errs <- character(); data <- list()
  s <- tryCatch(kotak_session(), error = function(e) e)
  if (inherits(s, "error")) return(list(data = data, errors = stats::setNames(rep(conditionMessage(s), length(symbols)), symbols)))
  tok <- tryCatch(kotak_token_of(symbols), error = function(e) { errs[["scrip_master"]] <<- conditionMessage(e); NULL })
  if (is.null(tok)) return(list(data = data, errors = errs))
  for (sym in names(tok)[is.na(tok)]) errs[[sym]] <- "not in Kotak NSE scrip master"
  tok <- tok[!is.na(tok)]
  today <- as.Date(format(Sys.time(), "%Y-%m-%d", tz = "Asia/Kolkata"))
  from <- today - if (range == "1d") 0 else 7
  iv <- c(`1m` = "1min", `5m` = "5min", `15m` = "15min", `30m` = "30min", `60m` = "60min")[[interval]]
  q <- tryCatch(parse_kotak_quotes(kotak_get(paste0("/script-details/1.0/quotes/neosymbol/",
                  paste0("nse_cm|", tok, collapse = ","), "/all"), s), tok),
                error = function(e) { errs[["quotes"]] <<- conditionMessage(e); list() })
  for (sym in names(tok)) {
    d <- tryCatch(parse_kotak_candles(kotak_get(sprintf("/market-data/1.0/historical/details?neosymbol=nse_cm|%s&fromdate=%s&todate=%s&interval=%s",
                                                        tok[[sym]], from, today, iv), s), sym),
                  error = function(e) { errs[[sym]] <<- conditionMessage(e); NULL })
    if (is.null(d) || !nrow(d)) { if (is.null(errs[sym]) || is.na(errs[sym])) errs[[sym]] <- "no data"; next }
    attr(d, "meta") <- q[[sym]] %||% list(prev_close = NA_real_, price = utils::tail(d$close, 1), volume = NA_real_, market_time = utils::tail(d$ts, 1))
    data[[sym]] <- d
  }
  list(data = data, errors = errs)
}

# Live fetcher used by the API: NSE symbols through Kotak Neo when configured, everything
# else (and any NSE symbol Kotak fails on) through Yahoo. Each symbol's source is kept.
fetch_intraday_auto <- function(symbols, interval = "1m", range = "1d") {
  nse <- symbols[grepl("\\.NS$", symbols)]
  k <- if (length(nse) && kotak_configured()) kotak_intraday_many(nse, interval, range) else list(data = list(), errors = character())
  rest <- setdiff(symbols, names(k$data))
  y <- if (length(rest)) fetch_intraday_many(rest, interval, range) else list(data = list(), errors = character())
  src <- c(stats::setNames(rep("kotak_neo", length(k$data)), names(k$data)), stats::setNames(rep("yahoo", length(y$data)), names(y$data)))
  data <- c(k$data, y$data)
  ke <- k$errors[!names(k$errors) %in% names(data)]          # a Kotak failure Yahoo covered is not an error
  list(data = data, errors = c(y$errors, if (length(ke)) stats::setNames(paste("kotak:", ke), names(ke))), source = src)
}
