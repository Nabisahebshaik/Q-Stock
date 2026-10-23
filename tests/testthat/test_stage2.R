synthetic_market <- function(n_days = 140, seed = 11) {
  p <- simulate_garch_prices(n_days = n_days, tickers = paste0("T", 1:8), seed = seed)
  p$market <- "SYN"
  p
}

test_that("walk distributions are valid probability rows on a kNN market graph", {
  p <- synthetic_market()
  R <- returns_wide(p)
  rho <- cor(R[2:61, ])
  g <- knn_graph(rho, 3)
  expect_true(isSymmetric(g$adj))
  expect_true(all(rowSums(g$adj) >= 3))
  Ps <- walk_distributions(g$adj, g$w, steps = 6, tau_max = 2, alpha = 0.85)
  for (m in names(Ps)) {
    expect_equal(dim(Ps[[m]]), c(8, 8), info = m)
    expect_true(all(Ps[[m]] >= -1e-12), info = m)
    expect_equal(unname(rowSums(Ps[[m]])), rep(1, 8), tolerance = 1e-8, info = m)
  }
})

test_that("graph features at date t ignore prices after t", {
  p <- synthetic_market()
  cut <- sort(unique(p$date))[100]
  tampered <- p
  fut <- tampered$date > cut
  tampered$close[fut] <- tampered$close[fut] * exp(rnorm(sum(fut), 0, 0.05))
  a <- graph_features_market(p, corr_window = 40, k = 3, steps = 5, tau_max = 1, alpha = 0.85)
  b <- graph_features_market(tampered, corr_window = 40, k = 3, steps = 5, tau_max = 1, alpha = 0.85)
  expect_equal(a[a$date <= cut, ], b[b$date <= cut, ], ignore_attr = TRUE)
  expect_false(isTRUE(all.equal(a[a$date > cut, ], b[b$date > cut, ])))
})

test_that("sentiment features use only bins strictly before the trading date", {
  days <- seq(as.Date("2024-01-01"), as.Date("2024-02-29"), by = "day")
  sent <- data.frame(day = days, n_articles = 5, tone = sin(seq_along(days)), ticker = "X")
  trading <- data.frame(ticker = "X", date = as.Date(c("2024-02-01", "2024-02-15")))
  f0 <- sentiment_features(trading, sent)
  s2 <- sent; s2$tone[s2$day >= as.Date("2024-02-15")] <- 100   # same-day and future news
  f1 <- sentiment_features(trading, s2)
  expect_equal(f0, f1)
  s3 <- sent; s3$tone[s3$day == as.Date("2024-02-14")] <- 100   # previous day is usable
  f2 <- sentiment_features(trading, s3)
  expect_false(isTRUE(all.equal(f0$sent_tone_3[2], f2$sent_tone_3[2])))
  expect_equal(f0[1, ], f2[1, ])
})

test_that("sentiment window means match a direct computation", {
  days <- seq(as.Date("2024-03-01"), by = "day", length.out = 20)
  sent <- data.frame(day = days, n_articles = 1:20, tone = (1:20) / 10, ticker = "X")
  f <- sentiment_features(data.frame(ticker = "X", date = days[15]), sent)
  use <- 12:14   # bins t-3 .. t-1
  expect_equal(f$sent_tone_3, sum(sent$tone[use] * sent$n_articles[use]) / sum(sent$n_articles[use]))
  expect_equal(f$sent_logvol_7, log1p(sum(sent$n_articles[8:14])))
})

test_that("walk-forward split embargoes labels that fall in the test month", {
  p <- simulate_garch_prices(n_days = 400, tickers = c("A", "B"), seed = 12); p$market <- "SYN"
  f <- build_features(p)
  for (m in as.list(walk_forward_folds(f$date, 6))) {
    sp <- wf_split(f, m, 6)
    expect_true(all(sp$train$label_date < m))
    expect_true(all(sp$train$date < min(sp$test$date)))
    expect_true(all(format(sp$test$date, "%Y-%m") == format(m, "%Y-%m")))
  }
})

test_that("walk-forward shows no skill on unpredictable synthetic data", {
  p <- simulate_garch_prices(n_days = 900, tickers = paste0("S", 1:4), seed = 13); p$market <- "SYN"
  f <- build_features(p)
  pr <- walk_forward(f, CLASSICAL_COLS, "logit", train_months = 12, min_train_rows = 200)
  m <- prediction_metrics(pr$y_up, pr$p_up)
  expect_lt(abs(m[["auc"]] - 0.5), 0.05)
})

test_that("backtest charges costs only on position changes", {
  preds <- data.frame(date = as.Date("2024-01-01") + 0:3, ticker = "A",
                      p_up = c(0.6, 0.6, 0.4, 0.6), next_ret = log(1.01))
  d <- backtest(preds, cost_bps = 10)
  expect_equal(d$cost, c(10, 0, 10, 10) / 1e4)
  expect_equal(d$gross, c(0.01, 0.01, 0, 0.01), tolerance = 1e-12)
})

test_that("DM test is centred on identical losses and detects a clear difference", {
  set.seed(14); a <- rnorm(500)
  expect_equal(dm_test(a, a + 0)[["mean_diff"]], 0)
  expect_lt(dm_test(a^2, a^2 + 0.5 + rnorm(500, 0, 0.1))[["p_value"]], 0.001)
})
