# Chart bars (R/bars.R): intraday roll-ups (DuckDB SQL vs base R), daily roll-ups, ranges,
# and the 5-second snapshot path with a mocked fetcher. Offline.

utc <- function(s) as.POSIXct(s, tz = "UTC")

# Synthetic 1-minute session bars on given local dates (exchange clock).
synth_1m <- function(ticker, mk, dates, seed = 1) {
  set.seed(seed); s <- LIVE$sessions[[mk]]
  do.call(rbind, lapply(dates, function(d) {
    o <- as.POSIXct(paste(d, s$open), tz = s$tz); cl <- as.POSIXct(paste(d, s$close), tz = s$tz)
    b <- seq(as.numeric(o), as.numeric(cl) - 60, by = 60)
    close <- 100 * exp(cumsum(rnorm(length(b), 0, 1e-3))); open <- c(close[1], head(close, -1))
    data.frame(ticker = ticker, bucket = as.POSIXct(b, origin = "1970-01-01", tz = "UTC"), open = open,
               high = pmax(open, close) * 1.0005, low = pmin(open, close) * 0.9995, close = close,
               volume = c(NA, rpois(length(b) - 1, 300)))
  }))
}

test_that("intraday roll-ups: DuckDB SQL equals base R, across a DST change, with Parquet history", {
  con <- candle_store_open(":memory:", "duckdb"); on.exit(candle_store_close(con))
  nse <- synth_1m("RELIANCE.NS", "NSE", c("2026-10-22", "2026-10-23"))
  nq <- synth_1m("AAPL", "NASDAQ", c("2026-10-30", "2026-11-02"), seed = 2)   # US DST ends 2026-11-01
  candle_upsert(con, rbind(nse, nq), 60, "test")
  for (w in c(300, 900, 1800, 3600)) {
    for (k in list(c("RELIANCE.NS", "NSE"), c("AAPL", "NASDAQ"))) {
      a <- rollup_intraday_duck(con, k[1], k[2], w)
      b <- rollup_intraday_r(candle_read(con, k[1], 60), k[2], w)
      expect_equal(a, b, info = paste(k, w))
      expect_true(all(a$high >= pmax(a$open, a$close) & a$low <= pmin(a$open, a$close)))
    }
  }
  h <- rollup_intraday_r(nse, "NSE", 3600)
  hm <- format(h$bucket, "%H:%M", tz = "Asia/Kolkata")
  expect_equal(unique(hm), c("09:15", "10:15", "11:15", "12:15", "13:15", "14:15", "15:15"))   # session-aligned
  expect_equal(sum(h$volume), sum(nse$volume, na.rm = TRUE))
  expect_equal(nrow(rollup_intraday_r(nse, "NSE", 300)), 2 * 75)
  q <- rollup_intraday_r(nq, "NASDAQ", 3600)
  expect_equal(unique(format(q$bucket, "%H:%M", tz = "America/New_York")), sprintf("%02d:30", 9:15))   # both sides of DST
  f <- rollup_intraday_r(nse, "NSE", 900); i <- f$bucket == utc("2026-10-22 03:45:00")
  first <- nse[nse$bucket < utc("2026-10-22 04:00:00"), ]
  expect_equal(c(f$open[i], f$high[i], f$low[i], f$close[i]), c(first$open[1], max(first$high), min(first$low), first$close[15]))
  # Parquet history: move the first NSE day out of the table; the SQL reads both
  pq <- file.path(tempdir(), "pq_bars"); unlink(pq, recursive = TRUE)
  duck_export_parquet(con, pq, as.numeric(utc("2026-10-23 00:00:00")))
  a <- rollup_intraday_duck(con, "RELIANCE.NS", "NSE", 900, parquet_dir = pq)
  expect_equal(a, rollup_intraday_r(nse, "NSE", 900))
  expect_equal(nrow(rollup_intraday_duck(con, "NOPE", "NSE", 300)), 0)
})

test_that("daily roll-ups: weeks start Monday, months on the 1st", {
  d <- data.frame(date = as.Date(c("2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01", "2026-10-02", "2026-10-05", "2026-10-06")),
                  open = 1:7, high = 11:17, low = c(0, 1, 2, 3, 4, 5, 6) - 1, close = 2:8, volume = c(1, 2, NA, 4, 5, 6, 7))
  w <- rollup_daily(d, "week")
  expect_equal(w$date, as.Date(c("2026-09-28", "2026-10-05")))
  expect_equal(w$open, c(1, 6)); expect_equal(w$high, c(15, 17)); expect_equal(w$low, c(-1, 4))
  expect_equal(w$close, c(6, 8)); expect_equal(w$volume, c(12, 13))
  m <- rollup_daily(d, "month")
  expect_equal(m$date, as.Date(c("2026-09-01", "2026-10-01")))
  expect_equal(m$close, c(4, 8)); expect_equal(m$volume, c(3, 22))
  expect_equal(weekdays(rollup_daily(data.frame(date = as.Date("2026-10-25"), open = 1, high = 1, low = 1, close = 1, volume = 1))$date), "Monday")
})

test_that("range start: sessions present for 1D/5D, calendar otherwise", {
  days <- as.Date(c("2026-10-14", "2026-10-15", "2026-10-16", "2026-10-19", "2026-10-20", "2026-10-21", "2026-10-23"))
  expect_equal(range_start("1D", days), as.Date("2026-10-23"))
  expect_equal(range_start("5D", days), as.Date("2026-10-16"))
  expect_equal(range_start("1M", days), as.Date("2026-09-23"))
  expect_equal(range_start("3M", days), as.Date("2026-07-23"))
  expect_equal(range_start("1Y", days), as.Date("2025-10-23"))
  expect_equal(range_start("5Y", days), as.Date("2021-10-23"))
  expect_equal(range_start("YTD", days), as.Date("2026-01-01"))
  expect_equal(range_start("ALL", days), as.Date("2026-10-14"))
  expect_equal(months_back(as.Date("2026-03-31"), 1), as.Date("2026-02-28"))
  expect_equal(range_start("5D", days[1:2]), as.Date("2026-10-14"))
  expect_match(range_note("5D", days[1:2], range_start("5D", days[1:2])), "2 session")
  expect_match(range_note("1M", days, range_start("1M", days)), "shorter")
  expect_null(range_note("1D", days, range_start("1D", days)))
  expect_error(range_start("2W", days), class = "qs_bad_request")
})

test_that("5-second snapshot bars: OHLC, volume deltas, at most one fetch per 2 s, closed market", {
  con <- candle_store_open(":memory:", "duckdb"); on.exit(candle_store_close(con))
  t0 <- as.numeric(utc("2026-10-23 05:00:00"))          # Friday 10:30 IST
  px <- 100 + c(0, 1, -1, 2, 3, 1, 0, 4, 2, 5, 1)
  cv <- 1000 + cumsum(c(0, 10, 5, 0, 20, 1, 2, 3, 4, 5, 6))
  calls <- 0; clock <- t0
  fx <- function(tk) { calls <<- calls + 1; list(price = px[calls], time = clock, volume = cv[calls]) }
  snap <- snapshot_state()
  for (t in t0 + 0:20) {
    clock <- t
    r <- snapshot_tick(snap, "NSE", "RELIANCE.NS", con, now = as.POSIXct(t, origin = "1970-01-01", tz = "UTC"), fetcher = fx)
    expect_true(r$open)
  }
  expect_equal(calls, 11)                                # fetches at t0, t0 + 2, ..., t0 + 20
  stored <- candle_read(con, "RELIANCE.NS", 5)
  expect_equal(nrow(stored), 3)                          # 0-5, 5-10, 10-15 closed by the watermark at t0 + 15
  expect_true(all(stored$source == "yahoo_snapshot"))
  b <- snapshot_bars(snap, "RELIANCE.NS", con)
  expect_equal(as.numeric(b$bucket) - t0, c(0, 5, 10, 15, 20))
  expect_equal(b$open, c(100, 102, 101, 102, 101))
  expect_equal(b$high, c(101, 103, 104, 105, 101))
  expect_equal(b$low, c(99, 102, 100, 102, 101))
  expect_equal(b$close, c(99, 103, 104, 105, 101))
  expect_equal(b$volume, c(15, 20, 6, 9, 6))              # first snapshot has no previous volume: 0
  sat <- as.POSIXct(t0 + 86400, origin = "1970-01-01", tz = "UTC")
  r <- snapshot_tick(snap, "NSE", "RELIANCE.NS", con, now = sat, fetcher = fx)
  expect_false(r$open); expect_false(r$fetched); expect_equal(calls, 11)
  bad <- snapshot_tick(snapshot_state(), "NSE", "TCS.NS", con, now = as.POSIXct(t0, origin = "1970-01-01", tz = "UTC"),
                       fetcher = function(tk) stop("timeout"))
  expect_false(bad$fetched); expect_equal(bad$error, "timeout")
})
