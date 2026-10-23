# Live market module: parsing, sessions, hot/cold split, idempotent store, tick aggregator.
# All tests run offline (fixtures and synthetic ticks); no network access.

utc <- function(s) as.POSIXct(s, tz = "UTC")

fixture_json <- function() {
  ts <- as.numeric(utc("2026-10-23 05:00:00")) + 60 * (0:3)
  jsonlite::toJSON(list(chart = list(result = list(list(
    meta = list(chartPreviousClose = 100, regularMarketPrice = 101.5, regularMarketTime = ts[4] + 25),
    timestamp = c(ts[1:3], ts[4] + 25),
    indicators = list(quote = list(list(open = list(100, 100.5, NULL, 101), high = list(100.6, 101, NULL, 101.6),
                                        low = list(99.9, 100.4, NULL, 100.9), close = list(100.5, 100.9, NULL, 101.5),
                                        volume = list(10, 20, NULL, 5)))))))), auto_unbox = TRUE, null = "null")
}

test_that("intraday parser keeps valid bars, drops null bars and reads meta", {
  d <- parse_intraday(as.character(fixture_json()), "TEST.NS")
  expect_equal(nrow(d), 3)
  expect_equal(d$close, c(100.5, 100.9, 101.5))
  expect_equal(attr(d, "meta")$prev_close, 100)
  expect_null(parse_intraday('{"chart":{"result":null}}', "X"))
})

test_that("market sessions follow exchange time zones and DST", {
  expect_true(market_status("NSE", utc("2026-10-23 05:00:00"))$open)          # 10:30 IST, Friday
  expect_false(market_status("NSE", utc("2026-10-23 10:05:00"))$open)         # 15:35 IST, after close
  expect_false(market_status("NSE", utc("2026-10-24 05:00:00"))$open)         # Saturday
  expect_true(market_status("NASDAQ", utc("2026-10-23 13:35:00"))$open)       # 09:35 EDT
  expect_false(market_status("NASDAQ", utc("2026-11-02 14:25:00"))$open)      # 09:25 EST (after DST ends)
  expect_true(market_status("NASDAQ", utc("2026-11-02 14:35:00"))$open)       # 09:35 EST
})

test_that("hot/cold split: only the still-forming bucket is active", {
  d <- parse_intraday(as.character(fixture_json()), "TEST.NS")
  now <- utc("2026-10-23 05:03:30")
  s <- split_active(d, 60, now, market_open = TRUE)
  expect_equal(nrow(s$active), 1); expect_equal(nrow(s$final), 2)
  expect_equal(s$active$bucket, utc("2026-10-23 05:03:00"))
  s2 <- split_active(d, 60, now, market_open = FALSE)
  expect_equal(nrow(s2$active), 0)
})

test_that("candle store upsert is idempotent, applies revisions and rejects bad bars", {
  con <- candle_store_open(":memory:"); on.exit(DBI::dbDisconnect(con))
  c1 <- data.frame(ticker = "A", bucket = utc("2026-10-23 05:00:00") + c(0, 60),
                   open = c(10, 11), high = c(11, 12), low = c(9, 10.5), close = c(11, 11.5), volume = c(5, 6))
  expect_equal(unname(candle_upsert(con, c1, 60, "test")), c(2, 0))
  candle_upsert(con, c1, 60, "test")                                     # replay
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM candles")$n, 2)
  c2 <- c1[2, ]; c2$close <- 11.8; c2$high <- 12.2                       # late revision
  candle_upsert(con, c2, 60, "test")
  r <- candle_read(con, "A", 60)
  expect_equal(r$close, c(11, 11.8)); expect_equal(r$high, c(11, 12.2))
  bad <- c1[1, ]; bad$bucket <- bad$bucket + 600; bad$high <- 8           # high < low
  expect_equal(unname(candle_upsert(con, bad, 60, "test")), c(0, 1))
  expect_equal(nrow(candle_read(con, "A", 60)), 2)
})

test_that("tick aggregator builds correct OHLCV with out-of-order ticks and a watermark", {
  agg <- tick_aggregator(60, grace_sec = 5)
  t0 <- as.numeric(utc("2026-10-23 05:00:00"))
  ticks <- data.frame(ticker = "A", ts = as.POSIXct(t0 + c(10, 5, 30, 50, 62), origin = "1970-01-01", tz = "UTC"),
                      price = c(101, 100, 103, 102, 104), size = c(1, 2, 3, 4, 5), id = paste0("t", 1:5))
  r <- agg_push(agg, ticks)
  expect_equal(nrow(r$finalized), 0)                       # watermark 05:00:57 < bucket end 05:01:00
  r <- agg_push(agg, data.frame(ticker = "A", ts = as.POSIXct(t0 + 66, origin = "1970-01-01", tz = "UTC"),
                                price = 104.5, size = 1, id = "t6"))
  expect_equal(nrow(r$finalized), 1)
  f <- r$finalized
  expect_equal(c(f$open, f$high, f$low, f$close, f$volume), c(100, 103, 100, 102, 10))   # open = earliest event
  expect_equal(nrow(agg_active(agg)), 1)
})

test_that("tick aggregator drops duplicates and emits late corrections", {
  agg <- tick_aggregator(60, grace_sec = 5)
  t0 <- as.numeric(utc("2026-10-23 05:00:00"))
  mk <- function(off, p, id) data.frame(ticker = "A", ts = as.POSIXct(t0 + off, origin = "1970-01-01", tz = "UTC"),
                                        price = p, size = 1, id = id)
  agg_push(agg, rbind(mk(10, 100, "a"), mk(70, 101, "b")))
  agg_push(agg, mk(70, 101, "b"))                                        # duplicate (reconnect replay)
  expect_equal(agg$stats[["duplicates"]], 1)
  r <- agg_push(agg, mk(30, 99, "c"))                                    # late tick for finalised 05:00
  expect_equal(nrow(r$corrected), 1)
  expect_equal(r$corrected$low, 99); expect_equal(r$corrected$close, 99)  # 05:00:30 is the latest tick of that bucket
  expect_equal(agg$stats[["late_corrections"]], 1)
})

test_that("aggregated candles do not depend on arrival order within the grace period", {
  set.seed(5)
  agg_a <- tick_aggregator(60, 5); agg_b <- tick_aggregator(60, 5)
  t0 <- as.numeric(utc("2026-10-23 05:00:00"))
  n <- 600
  ticks <- data.frame(ticker = sample(c("A", "B", "C"), n, TRUE),
                      ts = as.POSIXct(t0 + sort(runif(n, 0, 600)), origin = "1970-01-01", tz = "UTC"),
                      price = 100 + cumsum(rnorm(n, 0, 0.05)), size = rpois(n, 3) + 1)
  ticks$id <- seq_len(n)
  jitter <- order(as.numeric(ticks$ts) + runif(n, 0, 3))                 # arrival disorder < grace
  a <- rbind(agg_push(agg_a, ticks)$finalized, agg_flush(agg_a))
  b <- rbind(agg_push(agg_b, ticks[jitter, ])$finalized, agg_flush(agg_b))
  a <- a[order(a$ticker, a$bucket), ]; b <- b[order(b$ticker, b$bucket), ]
  expect_equal(nrow(a), nrow(b)); expect_equal(a[, -2], b[, -2], ignore_attr = TRUE)
  ref <- aggregate(size ~ ticker + floor(as.numeric(ts) / 60), ticks, sum)  # volume conservation
  expect_equal(sum(a$volume), sum(ref$size))
})

test_that("bar replay through the aggregator reproduces the bars", {
  bars <- data.frame(ticker = "A", bucket = utc("2026-10-23 05:00:00") + 60 * (0:4),
                     open = c(10, 11, 10.5, 10.8, 11.2), high = c(11.2, 11.3, 10.9, 11.4, 11.5),
                     low = c(9.8, 10.4, 10.2, 10.7, 11), close = c(11, 10.5, 10.8, 11.2, 11.1), volume = c(40, 8, 12, 20, 4))
  agg <- tick_aggregator(60, 5)
  out <- rbind(agg_push(agg, bars_to_ticks(bars))$finalized, agg_flush(agg))
  expect_equal(out[, c("open", "high", "low", "close", "volume")], bars[, c("open", "high", "low", "close", "volume")],
               ignore_attr = TRUE)
})

test_that("live graph and walk on intraday returns are valid distributions", {
  set.seed(9)
  bk <- utc("2026-10-23 03:45:00") + 60 * (0:120)
  tk <- paste0("S", 1:8)
  f <- cumsum(rnorm(length(bk), 0, 1e-3))
  bars <- do.call(rbind, lapply(tk, function(s) data.frame(ticker = s, bucket = bk,
           close = 100 * exp(f * runif(1, 0.5, 1.5) + cumsum(rnorm(length(bk), 0, 5e-4))))))
  R <- intraday_returns_wide(bars, last_n = 90)
  expect_equal(dim(R), c(90, 8))
  g <- live_graph(R)
  rv <- intraday_rv(bars, "NSE")
  expect_true(all(is.finite(rv) & rv > 0))
  w <- live_walk(g, 0.25, rv)
  expect_equal(unname(rowSums(attr(w, "P"))), rep(1, 8), tolerance = 1e-10)
  expect_true(all(w$q_self > 0 & w$q_self < 1))
  expect_true(all(w$q_volspill >= min(rv) - 1e-12 & w$q_volspill <= max(rv) + 1e-12))  # weighted mean
  expect_equal(colMeans(attr(w, "P")), rep(1 / 8, 8), tolerance = 1e-6)                 # doubly stochastic
})

test_that("live GHAR forecast drops a still-trading session", {
  sim <- simulate_garch_prices(n_days = 160, tickers = paste0("S", 1:8), seed = 3)
  sim$market <- "NSE"
  last <- max(sim$date)
  model <- list(coef = c(-1, 0.1, 0.3, 0.4, 0.05, 0.05, 0.05))
  open_now <- as.POSIXct(paste(last, "10:00"), tz = "Asia/Kolkata")
  if (!market_status("NSE", open_now)$open) skip("synthetic last date is not a weekday")
  f_open <- ghar_live_forecast(sim, model, "NSE", now = open_now)
  f_closed <- ghar_live_forecast(sim, model, "NSE", now = open_now + 8 * 3600)
  expect_true(all(f_open$as_of < last)); expect_true(all(f_closed$as_of == last))
  expect_true(all(is.finite(f_open$vol5_ann) & f_open$vol5_ann > 0))
})
