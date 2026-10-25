# Chart indicators (R/indicators.R): known values computed by hand on small vectors.

test_that("SMA and EMA (EMA seeded with the SMA of the first n values)", {
  expect_equal(sma(1:5, 3), c(NA, NA, 2, 3, 4))
  expect_equal(sma(1:2, 3), c(NA_real_, NA_real_))
  # alpha = 2 / (3 + 1) = 0.5; seed mean(2, 4, 6) = 4; then 0.5 * 8 + 0.5 * 4 = 6; 0.5 * 12 + 0.5 * 6 = 9
  expect_equal(ema(c(2, 4, 6, 8, 12), 3), c(NA, NA, 4, 6, 9))
  expect_equal(ema(c(1, 2), 3), c(NA_real_, NA_real_))
})

test_that("Bollinger bands use the population sd", {
  b <- bollinger(c(1, 2, 3, 4), 2, 2)          # sd of (1, 2) with divisor n is 0.5
  expect_equal(b$basis, c(NA, 1.5, 2.5, 3.5))
  expect_equal(b$upper, c(NA, 2.5, 3.5, 4.5))
  expect_equal(b$lower, c(NA, 0.5, 1.5, 2.5))
  b3 <- bollinger(c(2, 4, 9), 3, 1)            # mean 5, population sd sqrt(26/3)
  expect_equal(b3$upper[3], 5 + sqrt(26 / 3))
})

test_that("RSI uses Wilder smoothing", {
  x <- c(10, 11, 10.5, 11.5, 12, 11)
  # changes 1, -0.5, 1, 0.5, -1; seed: up 2/3, down 1/6 -> RS 4 -> 80
  # then up (2/3*2 + 0.5)/3 = 11/18, down (1/6*2)/3 = 1/9 -> RS 5.5; then both 11/27 -> 50
  expect_equal(rsi(x, 3), c(NA, NA, NA, 80, 100 - 100 / 6.5, 50))
  expect_equal(tail(rsi(1:10, 3), 1), 100)      # no down moves
  expect_equal(tail(rsi(10:1, 3), 1), 0)        # no up moves
  expect_true(all(is.na(rsi(1:3, 3))))
})

test_that("session VWAP resets per session and is NA before the first traded volume", {
  p <- c(10, 20, 30, 40)
  v <- vwap_session(p, p, p, c(0, 1, 3, 2), c(1, 1, 1, 2))
  expect_equal(v, c(NA, 20, (20 + 90) / 4, 40))
  v2 <- vwap_session(c(12, 12), c(6, 6), c(9, 9), c(NA, 5), c("a", "a"))   # typical price 9
  expect_equal(v2, c(NA, 9))
})

test_that("indicator specs are parsed and validated", {
  s <- parse_ind_spec("vwap,sma:20,ema:50,bb:20:2,rsi:14")
  expect_equal(vapply(s, `[[`, "", "id"), c("vwap", "sma:20", "ema:50", "bb:20:2", "rsi:14"))
  expect_equal(s[[4]]$params, list(n = 20L, k = 2))
  expect_length(parse_ind_spec(""), 0)
  expect_length(parse_ind_spec(NULL), 0)
  expect_length(parse_ind_spec("sma:20, SMA:20"), 1)
  expect_equal(parse_ind_spec("bb:10:1.5")[[1]]$id, "bb:10:1.5")
  for (bad in c("foo", "sma", "sma:1", "sma:501", "sma:2.5", "sma:x", "bb:20", "bb:20:0.1", "bb:20:6", "vwap:3", "rsi:14:2",
                paste(sprintf("sma:%d", 2:10), collapse = ",")))
    expect_error(parse_ind_spec(bad), class = "qs_bad_request")
})

test_that("compute_indicators: contract structure, trimming, VWAP intraday only", {
  set.seed(3); n <- 60; cl <- 100 + cumsum(rnorm(n))
  bars <- data.frame(time = 1:n * 60, open = cl, high = cl + 1, low = cl - 1, close = cl, volume = 10)
  keep <- seq_len(n) > 30
  s <- parse_ind_spec("vwap,sma:20,bb:20:2,rsi:14")
  out <- compute_indicators(bars, s, intraday = TRUE, session_id = rep(1:2, each = 30), keep = keep)
  expect_equal(vapply(out, `[[`, "", "id"), c("vwap", "sma:20", "bb:20:2", "rsi:14"))
  expect_equal(vapply(out, `[[`, "", "pane"), c("price", "price", "price", "rsi"))
  expect_equal(vapply(out[[3]]$lines, `[[`, "", "name"), c("BB basis", "BB upper", "BB lower"))
  sm <- out[[2]]$lines[[1]]$values
  expect_equal(sm$time, bars$time[31:60])                        # warm-up bars give values from the range start
  expect_equal(sm$value, round(sma(cl, 20)[31:60], 4))
  expect_equal(out[[1]]$lines[[1]]$values$value[1], round(cl[31], 4))   # session 2 starts at bar 31
  d <- compute_indicators(bars, s, intraday = FALSE)
  expect_false("vwap" %in% vapply(d, `[[`, "", "id"))
  expect_match(attr(d, "notes"), "VWAP")
  short <- compute_indicators(bars[1:5, ], parse_ind_spec("sma:20"))
  expect_equal(nrow(short[[1]]$lines[[1]]$values), 0)             # no value -> no point
})
