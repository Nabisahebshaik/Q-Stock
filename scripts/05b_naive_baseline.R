# Naive reference: predict the training window's up-frequency for every test row
# (same folds and embargo as walk_forward). Any useful model must beat its log-loss.
# The corresponding "strategy" is always long (p > 0.5 whenever ups dominate).

for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
ds <- readRDS(file.path(QS$paths$curated, "dataset_graph.rds"))
out <- list()
for (mk in c("NSE", "NASDAQ")) {
  d <- ds[ds$market == mk & complete.cases(ds[, c(CLASSICAL_COLS, "y_up", "label_date")]), ]
  preds <- list()
  for (m in as.list(walk_forward_folds(d$date))) {
    sp <- wf_split(d, m)
    if (nrow(sp$train) < QS$min_train_rows || nrow(sp$test) == 0) next
    preds[[length(preds) + 1]] <- data.frame(date = sp$test$date, ticker = sp$test$ticker,
                                             p_up = mean(sp$train$y_up), y_up = sp$test$y_up,
                                             next_ret = sp$test$next_ret)
  }
  pr <- do.call(rbind, preds)
  pm <- prediction_metrics(pr$y_up, pr$p_up)
  out[[mk]] <- data.frame(market = mk, n = nrow(pr), logloss_naive = pm[["logloss"]],
                          share_folds_predict_up = mean(tapply(pr$p_up, format(pr$date, "%Y-%m"), mean) > 0.5),
                          sharpe_net_naive = annualized_sharpe(backtest(pr)$net))
}
nb <- do.call(rbind, out)
print(nb)
write.csv(nb, file.path(QS$paths$tables, "naive_baseline.csv"), row.names = FALSE)
