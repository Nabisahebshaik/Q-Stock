# Chart indicators for /api/bars (docs/design/CHART_WORKSPACE.md §3), following the
# TradingView conventions so the values match what traders expect:
#   sma  simple moving average
#   ema  exponential, alpha = 2 / (n + 1), seeded with the SMA of the first n values
#   bb   Bollinger bands: SMA basis +- k * population sd of the same window
#   rsi  Wilder's RSI (RMA smoothing seeded with the SMA of the first n changes)
#   vwap session-anchored on the typical price (h + l + c) / 3
# Every function returns a vector as long as its input, NA where undefined.

bad_request <- function(msg)
  stop(structure(class = c("qs_bad_request", "error", "condition"), list(message = msg, call = NULL)))

sma <- function(x, n) {
  if (length(x) < n) return(rep(NA_real_, length(x)))
  as.numeric(stats::filter(x, rep(1 / n, n), sides = 1))
}

ema <- function(x, n) {
  N <- length(x); out <- rep(NA_real_, N)
  if (N < n) return(out)
  a <- 2 / (n + 1); out[n] <- mean(x[1:n])
  if (N > n) out[(n + 1):N] <- stats::filter(a * x[(n + 1):N], 1 - a, method = "recursive", init = out[n])
  out
}

# Population sd (divide by n), as TradingView's ta.stdev.
roll_sd <- function(x, n) {
  N <- length(x); out <- rep(NA_real_, N)
  if (N >= n) out[n:N] <- vapply(n:N, function(i) { w <- x[(i - n + 1):i]; sqrt(mean((w - mean(w))^2)) }, 0)
  out
}

bollinger <- function(x, n = 20, k = 2) {
  m <- sma(x, n); s <- roll_sd(x, n)
  list(basis = m, upper = m + k * s, lower = m - k * s)
}

rsi <- function(x, n = 14) {
  N <- length(x); out <- rep(NA_real_, N)
  if (N <= n) return(out)
  d <- diff(x); up <- pmax(d, 0); dn <- pmax(-d, 0)
  rma <- function(v) { a <- rep(NA_real_, length(v)); a[n] <- mean(v[1:n])
    if (length(v) > n) a[(n + 1):length(v)] <- stats::filter(v[(n + 1):length(v)] / n, 1 - 1 / n, method = "recursive", init = a[n])
    a }
  au <- rma(up); ad <- rma(dn)
  r <- ifelse(ad == 0, 100, ifelse(au == 0, 0, 100 - 100 / (1 + au / ad)))   # TradingView's edge cases
  out[-1] <- r
  out
}

# Cumulative typical-price VWAP, reset when session_id changes; NA until the session's
# first positive volume (a price with no traded volume has no volume-weighted average).
vwap_session <- function(high, low, close, volume, session_id) {
  v <- ifelse(is.finite(volume) & volume > 0, volume, 0)
  g <- factor(session_id, levels = unique(session_id))
  cv <- ave(v, g, FUN = cumsum); cpv <- ave((high + low + close) / 3 * v, g, FUN = cumsum)
  ifelse(cv > 0, cpv / cv, NA_real_)
}

# "vwap,sma:20,ema:50,bb:20:2,rsi:14" -> list of list(id, type, params). Duplicates are
# dropped; anything malformed is a 400 (qs_bad_request).
parse_ind_spec <- function(spec, max_n = 8) {
  if (is.null(spec) || !length(spec) || is.na(spec[1])) return(list())
  parts <- trimws(strsplit(tolower(paste(spec, collapse = ",")), ",", fixed = TRUE)[[1]])
  parts <- unique(parts[nzchar(parts)])
  if (length(parts) > max_n) bad_request(sprintf("at most %d indicators (got %d)", max_n, length(parts)))
  int_n <- function(s, p) {
    n <- suppressWarnings(as.numeric(s))
    if (is.na(n) || n != round(n) || n < 2 || n > 500) bad_request(sprintf("indicator %s: n must be an integer in 2..500", p))
    as.integer(n)
  }
  out <- lapply(parts, function(p) {
    a <- strsplit(p, ":", fixed = TRUE)[[1]]; ty <- a[1]; np <- length(a) - 1
    need <- c(vwap = 0, sma = 1, ema = 1, rsi = 1, bb = 2)
    if (!ty %in% names(need)) bad_request(sprintf("unknown indicator: %s", p))
    if (np != need[[ty]]) bad_request(sprintf("indicator %s: expected %d parameter(s)", p, need[[ty]]))
    if (ty == "vwap") return(list(id = "vwap", type = "vwap", params = setNames(list(), character())))
    n <- int_n(a[2], p)
    if (ty != "bb") return(list(id = sprintf("%s:%d", ty, n), type = ty, params = list(n = n)))
    k <- suppressWarnings(as.numeric(a[3]))
    if (is.na(k) || k < 0.5 || k > 5) bad_request(sprintf("indicator %s: k must be in 0.5..5", p))
    list(id = sprintf("bb:%d:%s", n, format(k)), type = "bb", params = list(n = n, k = k))
  })
  out[!duplicated(vapply(out, `[[`, "", "id"))]
}

# Indicator payload of the contract. bars: data.frame(time, open, high, low, close, volume)
# in time order, including warm-up bars; keep: which bars are inside the requested range
# (values outside it are computed but not returned). VWAP is intraday only: on daily and
# longer bars it is omitted and a note is attached (attr "notes").
compute_indicators <- function(bars, specs, intraday = TRUE, session_id = NULL, keep = rep(TRUE, nrow(bars)), digits = 4) {
  notes <- character(); x <- bars$close
  line <- function(name, v) {
    ok <- keep & is.finite(v)
    list(name = name, values = data.frame(time = bars$time[ok], value = round(v[ok], digits)))
  }
  out <- list()
  for (s in specs) {
    n <- s$params$n
    lines <- switch(s$type,
      vwap = if (intraday) list(line("VWAP", vwap_session(bars$high, bars$low, x, bars$volume,
                                                          if (is.null(session_id)) rep(1, nrow(bars)) else session_id))),
      sma = list(line(sprintf("SMA %d", n), sma(x, n))),
      ema = list(line(sprintf("EMA %d", n), ema(x, n))),
      rsi = list(line(sprintf("RSI %d", n), rsi(x, n))),
      bb = { b <- bollinger(x, n, s$params$k)
             list(line("BB basis", b$basis), line("BB upper", b$upper), line("BB lower", b$lower)) })
    if (is.null(lines)) { notes <- c(notes, "VWAP is session-anchored and shown on intraday intervals only"); next }
    out[[length(out) + 1]] <- list(id = s$id, type = s$type, pane = if (s$type == "rsi") "rsi" else "price",
                                   params = s$params, lines = lines)
  }
  attr(out, "notes") <- notes
  out
}
