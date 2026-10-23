test_that("HAR regressors ignore the future and the RV target uses exactly days t+1..t+5", {
  p <- simulate_garch_prices(n_days = 120, tickers = "A", seed = 31)
  v <- build_vol_targets(p)
  r <- c(NA, diff(log(p$close)))
  i <- 50
  expect_equal(v$y_lrv5[i], log(mean(r[(i + 1):(i + 5)]^2) + 1e-8))
  expect_equal(v$har_w[i], log(mean(r[(i - 4):i]^2) + 1e-8))
  expect_equal(v$label_date_rv[i], p$date[i + 5])
  p2 <- p; p2$close[p2$date > p$date[i]] <- p2$close[p2$date > p$date[i]] * 1.3
  v2 <- build_vol_targets(p2)
  expect_equal(v[1:i, HAR_COLS], v2[1:i, HAR_COLS])
})

test_that("regression walk-forward embargoes 5-day targets that end in the test month", {
  p <- simulate_garch_prices(n_days = 400, tickers = c("A", "B"), seed = 32)
  v <- build_vol_targets(p)
  for (m in as.list(walk_forward_folds(v$date, 6))) {
    sp <- wf_split(v[complete.cases(v), ], m, 6, "label_date_rv")
    expect_true(all(sp$train$label_date_rv < m))
  }
  pr <- walk_forward_reg(v, HAR_COLS, train_months = 6, min_train_rows = 100)
  expect_true(all(c("pred", "y") %in% names(pr)))
  expect_gt(cor(pr$pred, pr$y), 0)   # HAR has real skill on GARCH volatility
})

test_that("QSW features at omega = 0 match the v1 CTQW features", {
  p <- simulate_garch_prices(n_days = 90, tickers = paste0("T", 1:7), seed = 33); p$market <- "S"
  q <- qsw_features_market(p, 0, corr_window = 40, k = 3, tau_max = 2)
  g <- graph_features_market(p, corr_window = 40, k = 3, steps = 5, tau_max = 2, alpha = 0.85)
  m <- merge(q, g, by = c("date", "ticker"))
  expect_equal(m$q_self, m$ctqw_self, tolerance = 1e-6)
  expect_equal(m$q_ent, m$ctqw_ent, tolerance = 1e-6)
})

test_that("stationary bootstrap CI covers the mean and the statistics helpers behave", {
  set.seed(34); x <- rnorm(300, 1)
  ci <- stationary_boot_ci(x, reps = 300)
  expect_true(ci[["lo"]] < 1 && ci[["hi"]] > 1)
  expect_equal(qlike(log(2), log(2)), 0)
  expect_equal(holm_adjust(c(0.01, 0.04)), c(0.02, 0.04))
})
