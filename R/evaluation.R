# Prediction metrics, trading backtest and significance tests.

auc_score <- function(y, p) {
  r <- rank(p); n1 <- sum(y == 1); n0 <- sum(y == 0)
  if (n1 == 0 || n0 == 0) return(NA_real_)
  (sum(r[y == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}

prediction_metrics <- function(y, p, threshold = 0.5) {
  pred <- as.integer(p > threshold)
  tp <- sum(pred & y); fp <- sum(pred & !y); fn <- sum(!pred & y); tn <- sum(!pred & !y)
  prec <- if (tp + fp > 0) tp / (tp + fp) else NA
  rec <- tp / max(tp + fn, 1)
  f1 <- if (!is.na(prec) && prec + rec > 0) 2 * prec * rec / (prec + rec) else NA
  mcc_den <- sqrt(as.numeric(tp + fp) * (tp + fn) * (tn + fp) * (tn + fn))
  pc <- pmin(pmax(p, 1e-6), 1 - 1e-6)
  c(n = length(y), accuracy = mean(pred == y), f1 = f1,
    mcc = if (mcc_den > 0) (as.numeric(tp) * tn - as.numeric(fp) * fn) / mcc_den else 0,
    auc = auc_score(y, p), logloss = -mean(y * log(pc) + (1 - y) * log(1 - pc)))
}

# Long/flat strategy, equal-weighted across the tickers of one market.
# Position decided at the close of t (p_up > 0.5) and held to the close of t+1.
# Cost = cost_bps per unit of one-way turnover in each ticker's position.
backtest <- function(preds, cost_bps = QS$cost_bps) {
  preds <- preds[order(preds$ticker, preds$date), ]
  preds$pos <- as.integer(preds$p_up > 0.5)
  preds$prev_pos <- ave(preds$pos, preds$ticker, FUN = function(x) c(0, head(x, -1)))
  preds$gross <- preds$pos * (exp(preds$next_ret) - 1)
  preds$cost <- abs(preds$pos - preds$prev_pos) * cost_bps / 1e4
  preds$bh <- exp(preds$next_ret) - 1
  daily <- aggregate(cbind(gross, cost, bh, pos) ~ date, preds, mean)
  daily$net <- daily$gross - daily$cost
  daily[order(daily$date), ]
}

annualized_sharpe <- function(r) if (sd(r) > 0) mean(r) / sd(r) * sqrt(252) else NA_real_

strategy_metrics <- function(daily) {
  c(sharpe_net = annualized_sharpe(daily$net), sharpe_gross = annualized_sharpe(daily$gross),
    sharpe_buyhold = annualized_sharpe(daily$bh),
    ann_return_net = mean(daily$net) * 252, ann_vol_net = sd(daily$net) * sqrt(252),
    max_drawdown_net = { eq <- cumprod(1 + daily$net); max(1 - eq / cummax(eq)) },
    avg_exposure = mean(daily$pos), turnover_cost_ann = mean(daily$cost) * 252)
}

# Diebold-Mariano test on two aligned loss series (Newey-West variance).
dm_test <- function(loss_a, loss_b, lag = 5) {
  d <- loss_a - loss_b; n <- length(d); dc <- d - mean(d)
  v <- sum(dc^2) / n
  for (k in seq_len(lag)) v <- v + 2 * (1 - k / (lag + 1)) * sum(dc[-(1:k)] * dc[1:(n - k)]) / n
  stat <- mean(d) / sqrt(v / n)
  c(dm_stat = stat, p_value = 2 * pnorm(-abs(stat)), mean_diff = mean(d))
}

# Stationary bootstrap (Politis-Romano) CI for the mean of a dependent series.
stationary_boot_ci <- function(x, mean_block = 20, reps = 2000, level = 0.95, seed = 1) {
  set.seed(seed); n <- length(x); p <- 1 / mean_block
  stats <- replicate(reps, {
    idx <- integer(n); idx[1] <- sample.int(n, 1)
    for (i in 2:n) idx[i] <- if (runif(1) < p) sample.int(n, 1) else (idx[i - 1] %% n) + 1
    mean(x[idx])
  })
  a <- (1 - level) / 2
  c(mean = mean(x), lo = unname(quantile(stats, a)), hi = unname(quantile(stats, 1 - a)))
}

holm_adjust <- function(p) p.adjust(p, method = "holm")
bh_adjust <- function(p) p.adjust(p, method = "BH")

# QLIKE loss for variance forecasts given log targets/predictions.
qlike <- function(y_log, pred_log) { r <- exp(y_log - pred_log); r - log(r) - 1 }

# Daily cross-sectional Spearman rank IC and its Newey-West t-statistic.
rank_ic <- function(preds, score = "p_up", outcome = "next_ret", lag = 5) {
  ic <- sapply(split(preds, preds$date), function(d)
    if (nrow(d) >= 5) suppressWarnings(cor(d[[score]], d[[outcome]], method = "spearman")) else NA)
  ic <- ic[is.finite(ic)]
  dc <- ic - mean(ic); n <- length(ic); v <- sum(dc^2) / n
  for (k in seq_len(lag)) v <- v + 2 * (1 - k / (lag + 1)) * sum(dc[-(1:k)] * dc[1:(n - k)]) / n
  c(mean_ic = mean(ic), nw_t = mean(ic) / sqrt(v / n), n_days = n)
}

# Per-date mean log-loss, used to compare two prediction sets with DM.
daily_logloss <- function(preds) {
  pc <- pmin(pmax(preds$p_up, 1e-6), 1 - 1e-6)
  preds$ll <- -(preds$y_up * log(pc) + (1 - preds$y_up) * log(1 - pc))
  aggregate(ll ~ date, preds, mean)
}
