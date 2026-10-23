test_that("features at date t do not change when future prices change", {
  prices <- simulate_garch_prices(n_days = 120, tickers = "SYN_A", seed = 3)
  cut <- prices$date[80]
  tampered <- prices
  future <- tampered$date > cut
  tampered$close[future] <- tampered$close[future] * 1.5
  tampered$high[future] <- tampered$high[future] * 1.5
  tampered$low[future] <- tampered$low[future] * 1.5
  f1 <- build_features(prices); f2 <- build_features(tampered)
  past1 <- f1[f1$date <= cut, FEATURE_COLS]
  past2 <- f2[f2$date <= cut, FEATURE_COLS]
  expect_equal(past1, past2)
})

test_that("a missing value only affects the trailing windows that contain it", {
  x <- c(1:10, NA, 12:30)
  m <- trailing_mean(x, 5)
  expect_true(all(is.na(m[11:15])))
  expect_equal(m[16:30], sapply(16:30, function(i) mean(x[(i - 4):i])))
  expect_equal(m[5:10], sapply(5:10, function(i) mean(x[(i - 4):i])))
})

test_that("market-wide zero-volume bars are dropped as holidays", {
  d <- data.frame(date = rep(as.Date("2024-01-01") + 0:2, each = 4), ticker = rep(letters[1:4], 3),
                  market = "M", open = 10, high = 11, low = 9, close = 10, adj_close = 10,
                  volume = c(rep(100, 4), 0, 0, 0, 100, 100, 0, 100, 100))
  cl <- clean_prices(d)
  expect_equal(cl$issues$holiday_bars_dropped, 4)
  expect_false(as.Date("2024-01-02") %in% cl$data$date)
  expect_equal(sum(is.na(cl$data$volume)), 1)
})

test_that("label is the next-day direction", {
  f <- build_features(simulate_garch_prices(n_days = 60, tickers = "SYN_A", seed = 4))
  expect_equal(f$y_up[-nrow(f)], as.integer(f$ret_1[-1] > 0))
})

test_that("chronological split has no date overlap", {
  f <- build_features(simulate_garch_prices(n_days = 200, seed = 5))
  sp <- chrono_split(f, 0.7)
  expect_lt(max(sp$train$date), min(sp$test$date))
})

test_that("baseline shows no skill on unpredictable synthetic data (leakage canary)", {
  f <- build_features(simulate_garch_prices(n_days = 1000, seed = 6))
  res <- fit_logit_baseline(f)
  # With ~900 test rows the 99% band around 0.5 is roughly +/- 0.04.
  expect_lt(abs(res$test_metrics[["accuracy"]] - 0.5), 0.06)
})
