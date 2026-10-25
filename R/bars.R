# Bars for the chart workspace (docs/design/CHART_WORKSPACE.md §2): roll-ups of the 1-minute
# candle store to 5m..1h, daily -> weekly/monthly, range -> start-date helper, and the 5-second
# snapshot path. Bars here are data.frame(bucket [POSIXct UTC, true bucket start], open, high,
# low, close, volume) for intraday and data.frame(date, open, high, low, close, volume) for daily.

BAR_INTERVALS <- c(`5s` = 5, `1m` = 60, `5m` = 300, `15m` = 900, `30m` = 1800, `1h` = 3600,
                   `1d` = 86400, `1w` = 7 * 86400, `1mo` = 30 * 86400)
BAR_RANGES <- c("1D", "5D", "1M", "3M", "6M", "YTD", "1Y", "5Y", "ALL")

# OHLCV aggregation of time-ordered rows by key (first open, max high, min low, last close,
# summed volume; NA volume only when every row of the group is NA, like SQL SUM).
agg_ohlc <- function(d, key) {
  k <- factor(key, levels = unique(key)); f <- !duplicated(k); l <- !duplicated(k, fromLast = TRUE)
  v <- tapply(d$volume, k, function(x) if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE))
  data.frame(key = key[f], open = d$open[f], high = as.numeric(tapply(d$high, k, max)),
             low = as.numeric(tapply(d$low, k, min)), close = d$close[l], volume = as.numeric(v), row.names = NULL)
}

session_open_sec <- function(mk) {
  hm <- as.numeric(strsplit(LIVE$sessions[[mk]]$open, ":", fixed = TRUE)[[1]]); hm[1] * 3600 + hm[2] * 60
}

# Session-aligned bucket start (true epoch) of width w on the exchange-local clock, so 1h
# NSE bars start 09:15, 10:15, ... and NASDAQ 09:30, 10:30, ... (TradingView's alignment).
local_bucket <- function(epoch, mk, w) {
  off <- as.POSIXlt(as.POSIXct(epoch, origin = "1970-01-01", tz = "UTC"), tz = LIVE$sessions[[mk]]$tz)$gmtoff
  loc <- epoch + off; o <- session_open_sec(mk)
  floor((loc - o) / w) * w + o - off
}

# Base-R roll-up of 1-minute bars (any order) to width w seconds.
rollup_intraday_r <- function(bars, mk, w) {
  if (!NROW(bars)) return(empty_bars())
  bars <- bars[order(bars$bucket), ]
  r <- agg_ohlc(bars, local_bucket(as.numeric(bars$bucket), mk, w))
  data.frame(bucket = as.POSIXct(r$key, origin = "1970-01-01", tz = "UTC"), r[, -1])
}

empty_bars <- function() data.frame(bucket = as.POSIXct(numeric(), origin = "1970-01-01", tz = "UTC"),
                                    open = numeric(), high = numeric(), low = numeric(), close = numeric(), volume = numeric())

# The same roll-up in DuckDB over the store (table + Parquet history, table wins).
# DuckDB here has no ICU time zones, so R supplies the UTC offset of each UTC day (taken at
# 12:00 UTC: both sessions lie within one UTC day and after any 02:00-local DST switch).
rollup_intraday_duck <- function(con, ticker, mk, w, since = 0, parquet_dir = NULL) {
  glob <- duck_pq_glob(parquet_dir)
  where <- "ticker = ? AND interval_sec = 60 AND bucket_start >= ?"
  src <- if (is.null(glob)) sprintf("SELECT bucket_start, open, high, low, close, volume FROM candles WHERE %s", where) else
    sprintf("SELECT bucket_start, open, high, low, close, volume FROM (
               SELECT %s, 0 AS pri FROM candles WHERE %s
               UNION ALL SELECT %s, 1 AS pri FROM %s WHERE %s AND day >= CAST(? AS DATE))
             QUALIFY row_number() OVER (PARTITION BY bucket_start ORDER BY pri) = 1", DUCK_COLS, where, DUCK_COLS, duck_pq_from(glob), where)
  p <- list(ticker, as.numeric(since)); if (!is.null(glob)) p <- c(p, p, list(day_utc(since)))
  span <- DBI::dbGetQuery(con, sprintf("SELECT min(bucket_start) a, max(bucket_start) b FROM (%s)", src), params = p)
  if (is.na(span$a)) return(empty_bars())
  ud <- seq(floor(span$a / 86400), floor(span$b / 86400))
  tzd <- data.frame(uday = ud, off = as.POSIXlt(as.POSIXct(ud * 86400 + 43200, origin = "1970-01-01", tz = "UTC"),
                                                 tz = LIVE$sessions[[mk]]$tz)$gmtoff)
  tmp <- paste0("tzd_", paste(sample(letters, 10, TRUE), collapse = ""))
  duckdb::duckdb_register(con, tmp, tzd); on.exit(duckdb::duckdb_unregister(con, tmp))
  o <- session_open_sec(mk)
  sql <- sprintf("WITH c AS (%s),
    k AS (SELECT c.*, z.off, epoch(time_bucket(INTERVAL (%d) SECOND, make_timestamp(CAST(c.bucket_start + z.off AS BIGINT) * 1000000),
                                        TIMESTAMP '2000-01-03 00:00:00' + INTERVAL (%d) SECOND)) - z.off AS bk
          FROM c JOIN %s z ON z.uday = CAST(floor(c.bucket_start / 86400.0) AS BIGINT))
    SELECT bk, arg_min(open, bucket_start) AS open, max(high) AS high, min(low) AS low,
           arg_max(close, bucket_start) AS close, sum(volume) AS volume
    FROM k GROUP BY bk ORDER BY bk", src, as.integer(w), as.integer(o), tmp)
  d <- DBI::dbGetQuery(con, sql, params = p)
  data.frame(bucket = as.POSIXct(as.numeric(d$bk), origin = "1970-01-01", tz = "UTC"), open = d$open, high = d$high,
             low = d$low, close = d$close, volume = as.numeric(d$volume))
}

# Daily -> weekly (weeks start Monday) or monthly; a period is labelled by its first day.
rollup_daily <- function(d, period = c("week", "month")) {
  period <- match.arg(period)
  if (!NROW(d)) return(d[, c("date", "open", "high", "low", "close", "volume")])
  d <- d[order(d$date), ]
  key <- if (period == "week") d$date - (as.POSIXlt(d$date)$wday + 6) %% 7 else as.Date(format(d$date, "%Y-%m-01"))
  r <- agg_ohlc(d, key); names(r)[1] <- "date"; r$date <- as.Date(r$date)
  r
}

months_back <- function(d, m) {   # calendar months back, day clamped to the month's end (Mar 31 -> Feb 28)
  lt <- as.POSIXlt(d); y <- lt$year + 1900; mo <- lt$mon + 1 - m
  y <- y + (mo - 1) %/% 12; mo <- (mo - 1) %% 12 + 1
  first <- as.Date(sprintf("%04d-%02d-01", y, mo))
  last_day <- as.numeric(format(seq(first, by = "month", length.out = 2)[2] - 1, "%d"))
  first + min(lt$mday, last_day) - 1
}

# First session date of a range, given the session dates present in the data.
# 1D/5D = the last 1/5 sessions present; 1M..5Y calendar back from the last bar; YTD; ALL.
range_start <- function(range, days) {
  days <- sort(unique(as.Date(days)))
  if (!length(days)) return(as.Date(NA))
  last <- max(days)
  switch(range,
    `1D` = rev(days)[min(1, length(days))], `5D` = rev(days)[min(5, length(days))],
    `1M` = months_back(last, 1), `3M` = months_back(last, 3), `6M` = months_back(last, 6),
    `1Y` = months_back(last, 12), `5Y` = months_back(last, 60),
    YTD = as.Date(format(last, "%Y-01-01")), ALL = min(days),
    bad_request(paste("unknown range:", range)))
}

# Note when the data do not reach as far back as the range asks.
range_note <- function(range, days, start) {
  days <- unique(as.Date(days))
  if (range %in% c("1D", "5D")) {
    n <- if (range == "1D") 1 else 5
    if (length(days) < n) return(sprintf("history shorter than %s: %d session(s) available", range, length(days)))
  } else if (range != "ALL" && length(days) && min(days) > start + 3)
    return(sprintf("history shorter than %s: data from %s", range, format(min(days))))
  NULL
}

# ---- 5-second snapshot bars ----
# There is no free tick feed: a 5s bar is built from 2 s price snapshots (Yahoo meta
# regularMarketPrice / regularMarketTime / regularMarketVolume). Bar volume is the change in
# cumulative day volume between snapshots, so the first snapshot of a ticker contributes 0.

snapshot_state <- function() new.env()

snapshot_ticker <- function(snap, ticker) {
  if (is.null(snap[[ticker]])) snap[[ticker]] <- list2env(list(agg = tick_aggregator(5), last_fetch = -Inf, last_vol = NA_real_))
  snap[[ticker]]
}

# One fetch at most per ticker per `min_gap` seconds, and only while the market is open.
# Returns list(fetched, open, written, error).
snapshot_tick <- function(snap, mk, ticker, con, now = Sys.time(), min_gap = 2,
                          fetcher = getOption("qstock.snapshot_fetcher", fetch_snapshot)) {
  st <- market_status(mk, now); s <- snapshot_ticker(snap, ticker); tn <- as.numeric(now)
  res <- list(fetched = FALSE, open = isTRUE(st$open), written = 0L, error = NULL)
  if (!res$open || tn - s$last_fetch < min_gap) return(res)
  s$last_fetch <- tn
  q <- tryCatch(fetcher(ticker), error = function(e) e)
  if (inherits(q, "error") || is.null(q) || !is.finite(q$price %||% NA_real_)) {
    res$error <- if (inherits(q, "error")) conditionMessage(q) else "no price"; return(res)
  }
  res$fetched <- TRUE
  v <- as.numeric(q$volume %||% NA_real_)
  size <- if (is.finite(v) && is.finite(s$last_vol)) max(0, v - s$last_vol) else 0
  if (is.finite(v)) s$last_vol <- v
  ts <- as.numeric(q$time %||% NA_real_); if (!is.finite(ts)) ts <- tn
  tk <- data.frame(ticker = ticker, ts = as.POSIXct(ts, origin = "1970-01-01", tz = "UTC"), price = q$price, size = size,
                   id = paste(ticker, ts, v, sep = "|"))   # an unchanged snapshot is a duplicate, not a new trade
  r <- agg_push(s$agg, tk)
  # Wall clock also moves the watermark: with no new trades a bar still closes on time.
  fin <- rbind(r$finalized, r$corrected, agg_advance(s$agg, max(s$agg$max_event, tn) - s$agg$grace))
  if (nrow(fin)) res$written <- candle_upsert(con, fin, 5, "yahoo_snapshot")[["written"]]
  res
}

# Stored 5s bars plus the forming one.
snapshot_bars <- function(snap, ticker, con, since = 0) {
  d <- candle_read(con, ticker, 5, since)
  cols <- c("bucket", "open", "high", "low", "close", "volume")
  act <- if (!is.null(snap[[ticker]])) agg_active(snap[[ticker]]$agg) else NULL
  x <- rbind(d[, cols], if (NROW(act)) act[act$ticker == ticker, cols])
  if (!nrow(x)) return(empty_bars())
  x <- x[order(x$bucket), ]; x[!duplicated(x$bucket, fromLast = TRUE), ]
}
