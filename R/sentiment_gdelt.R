# Point-in-time news sentiment from the GDELT DOC 2.0 API.
#
# GDELT returns, per UTC calendar day, the average tone of matching articles
# (mode=timelinetone) and the raw article count (mode=timelinevolraw).
#
# Point-in-time rule (conservative): the feature row for trading date t uses
# only GDELT day bins whose UTC day ENDS strictly before the market close of t.
# NSE closes 15:30 IST (10:00 UTC) and NASDAQ 16:00 ET (20:00/21:00 UTC), so
# the newest usable bin is UTC day t-1 for both markets. Same-day news is never
# used. Caveat: GDELT is queried today, so the archive may contain articles
# that were indexed after their bin date; this residual risk is documented.

# Search phrases. Ambiguous company names get a disambiguating phrase.
SENTIMENT_QUERY_OVERRIDES <- c(
  AAPL = '"Apple Inc" OR "Apple shares" OR "Apple stock"',
  ITC.NS = '"ITC Ltd" OR "ITC shares" OR "ITC Limited"',
  INTC = '"Intel Corp" OR "Intel shares" OR "Intel stock"',
  AMZN = '"Amazon.com" OR "Amazon shares" OR "Amazon stock"',
  TSLA = '"Tesla Inc" OR "Tesla shares" OR "Tesla stock"',
  COST = '"Costco"', LT.NS = '"Larsen & Toubro" OR "Larsen and Toubro"',
  META = '"Meta Platforms" OR "Facebook Inc"', GOOGL = '"Alphabet Inc" OR "Google shares"',
  TITAN.NS = '"Titan Company"', CMCSA = '"Comcast"'
)

sentiment_query <- function(ticker, name) {
  q <- if (ticker %in% names(SENTIMENT_QUERY_OVERRIDES)) SENTIMENT_QUERY_OVERRIDES[[ticker]] else
    sprintf('"%s"', name)
  if (grepl(" OR ", q)) q <- paste0("(", q, ")")
  paste(q, "sourcelang:english")
}

gdelt_timeline <- function(query, mode, start, end, max_tries = 8) {
  url <- paste0("https://api.gdeltproject.org/api/v2/doc/doc?query=",
                utils::URLencode(query, reserved = TRUE),
                "&mode=", mode, "&format=json",
                "&startdatetime=", format(start, "%Y%m%d000000"),
                "&enddatetime=", format(end, "%Y%m%d235959"))
  wait <- 30
  h <- curl::new_handle(connecttimeout = 60, timeout = 300)
  for (i in seq_len(max_tries)) {
    resp <- tryCatch(curl::curl_fetch_memory(url, handle = h), error = function(e)
      list(status_code = -1L, content = charToRaw(conditionMessage(e))))
    txt <- rawToChar(resp$content)
    if (resp$status_code == 200 && startsWith(trimws(txt), "{")) {
      js <- jsonlite::fromJSON(txt)
      if (length(js$timeline) == 0) return(data.frame(day = as.Date(character()), value = numeric()))
      d <- js$timeline$data[[1]]
      return(data.frame(day = as.Date(substr(d$date, 1, 8), "%Y%m%d"), value = as.numeric(d$value)))
    }
    Sys.sleep(wait); wait <- min(wait * 2, 300)
  }
  stop(sprintf("GDELT failed after %d tries (last HTTP %d): %s", max_tries, resp$status_code,
               substr(txt, 1, 120)))
}

# Fetch tone + article counts for every ticker; GDELT DOC coverage starts in 2017.
load_sentiment <- function(refresh = FALSE, start = as.Date("2017-01-01"), pause = 20) {
  f <- file.path(QS$paths$raw, "sentiment_gdelt_daily.csv")
  if (file.exists(f) && !refresh) {
    s <- read.csv(f, stringsAsFactors = FALSE); s$day <- as.Date(s$day); return(s)
  }
  parts <- list()
  cache_dir <- file.path(QS$paths$raw, "gdelt_cache")
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  for (mk in names(QS$universe)) for (tk in names(QS$universe[[mk]])) {
    cf <- file.path(cache_dir, paste0(tk, ".csv"))
    if (file.exists(cf)) {
      parts[[tk]] <- read.csv(cf, stringsAsFactors = FALSE); parts[[tk]]$day <- as.Date(parts[[tk]]$day)
      next
    }
    q <- sentiment_query(tk, QS$universe[[mk]][[tk]])
    message("gdelt ", tk, ": ", q)
    tone <- gdelt_timeline(q, "timelinetone", start, QS$end_date); Sys.sleep(pause)
    vol <- gdelt_timeline(q, "timelinevolraw", start, QS$end_date); Sys.sleep(pause)
    m <- merge(setNames(vol, c("day", "n_articles")), setNames(tone, c("day", "tone")),
               by = "day", all = TRUE)
    m$n_articles[is.na(m$n_articles)] <- 0
    m$tone[m$n_articles == 0] <- NA
    m$ticker <- tk; m$query <- q
    write.csv(m, cf, row.names = FALSE)
    parts[[tk]] <- m
  }
  s <- do.call(rbind, parts); rownames(s) <- NULL
  write.csv(s, f, row.names = FALSE)
  s
}

# Align daily sentiment to trading dates under the point-in-time rule above.
# For trading date t and window w (calendar days), use bins t-w .. t-1.
#   sent_tone_w   : article-weighted mean tone over the window
#   sent_decay_w  : exponentially decayed tone, half-life w days, over the past 3w days
#   sent_logvol_7 : log(1 + articles) over the past 7 days
# Days with no articles contribute no tone; if a window has no articles the
# tone feature is 0 (neutral) and sent_logvol_7 records the absence of news.
trailing_weighted_sum <- function(x, weights) {
  # y[d] = sum_{a=0}^{L-1} weights[a+1] * x[d-a]   (only past and current values)
  as.numeric(stats::filter(c(rep(0, length(weights) - 1), x), weights, sides = 1))[-seq_len(length(weights) - 1)]
}

sentiment_features <- function(trading, sent, lag_days = 1) {
  out <- lapply(split(trading, trading$ticker), function(td) {
    s <- sent[sent$ticker == td$ticker[1], ]
    res <- matrix(0, nrow(td), length(SENTIMENT_COLS), dimnames = list(NULL, SENTIMENT_COLS))
    if (nrow(s) > 0) {
      # Dense daily calendar of article counts and tone*count.
      cal <- seq(min(s$day, min(td$date) - 30), max(s$day, max(td$date)), by = "day")
      n <- numeric(length(cal)); wt <- numeric(length(cal))
      k <- match(s$day, cal)
      n[k] <- s$n_articles; wt[k] <- ifelse(is.na(s$tone), 0, s$tone) * s$n_articles
      ratio <- function(num, den) ifelse(den > 0, num / den, 0)
      box <- function(w) rep(1, w)
      dec <- function(h) 0.5^((0:(3 * h - 1)) / h)
      feats <- cbind(
        sent_tone_3  = ratio(trailing_weighted_sum(wt, box(3)), trailing_weighted_sum(n, box(3))),
        sent_tone_7  = ratio(trailing_weighted_sum(wt, box(7)), trailing_weighted_sum(n, box(7))),
        sent_decay_3 = ratio(trailing_weighted_sum(wt, dec(3)), trailing_weighted_sum(n, dec(3))),
        sent_decay_7 = ratio(trailing_weighted_sum(wt, dec(7)), trailing_weighted_sum(n, dec(7))),
        sent_logvol_7 = log1p(trailing_weighted_sum(n, box(7))))
      # Row for trading date t reads the calendar at t - lag_days (newest usable bin).
      idx <- match(td$date - lag_days, cal)
      res[!is.na(idx), ] <- feats[idx[!is.na(idx)], SENTIMENT_COLS]
    }
    cbind(td[, c("ticker", "date")], res)
  })
  out <- do.call(rbind, out); rownames(out) <- NULL
  out
}
