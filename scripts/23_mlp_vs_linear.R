# GPU MLP (QLIKE-trained, scripts/18) versus the linear forecasters of scripts/20 on
# identical rows (same folds, same test dates and tickers). Exploratory, reported in full.
#   Rscript scripts/23_mlp_vs_linear.R
# Note: the MLP is trained on QLIKE, whose optimum for a log-variance forecast is
# log E[RV] rather than E[log RV]. Its forecasts are therefore biased upwards on the log scale,
# which MSE (log scale) penalises. QLIKE is the MLP's own loss and the standard robust
# volatility loss, so it is the primary comparison here; MSE is reported for completeness.
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
pd <- file.path(QS$paths$results, "predictions_v2")
mlp <- readRDS(file.path(pd, "mlp_qlike_gpu.rds"))
lin <- readRDS(file.path(pd, "tuned_models.rds"))
mw <- reshape(mlp[, c("market", "date", "ticker", "model", "pred")], idvar = c("market", "date", "ticker"),
              timevar = "model", direction = "wide")
names(mw) <- sub("^pred\\.", "MLP ", names(mw))
d <- merge(lin[, c("market", "date", "ticker", "y", "HAR", "GHAR", "Combo")], mw, by = c("market", "date", "ticker"))
stopifnot(nrow(d) == nrow(lin), nrow(d) == nrow(mlp) / 3)       # identical rows, nothing dropped
models <- c("HAR", "GHAR", "Combo", "MLP GHAR", "MLP GHAR+QSW w=0.25", "MLP GHAR+QSW w=1")

S <- do.call(rbind, lapply(split(d, d$market), function(x) do.call(rbind, lapply(models, function(m) {
  e <- x$y - x[[m]]
  data.frame(market = x$market[1], model = m, n = nrow(x), mse = mean(e^2), qlike = mean(qlike(x$y, x[[m]])),
             oos_r2 = 1 - sum(e^2) / sum((x$y - mean(x$y))^2), mean_bias = mean(x[[m]] - x$y))
}))))
cmp <- list(c("MLP GHAR", "GHAR"), c("MLP GHAR+QSW w=0.25", "GHAR"), c("MLP GHAR+QSW w=1", "GHAR"),
            c("MLP GHAR+QSW w=0.25", "MLP GHAR"), c("MLP GHAR+QSW w=0.25", "MLP GHAR+QSW w=1"))
T <- do.call(rbind, lapply(split(d, d$market), function(x) do.call(rbind, lapply(c("mse", "qlike"), function(ls) {
  L <- sapply(models, function(m) tapply(if (ls == "mse") (x$y - x[[m]])^2 else qlike(x$y, x[[m]]), x$date, mean))
  do.call(rbind, lapply(cmp, function(cp) {
    dl <- L[, cp[1]] - L[, cp[2]]; dm <- dm_test(L[, cp[1]], L[, cp[2]]); ci <- stationary_boot_ci(dl, reps = 1000)
    data.frame(market = x$market[1], loss = ls, a = cp[1], b = cp[2], mean_diff = mean(dl), ci_lo = ci[["lo"]],
               ci_hi = ci[["hi"]], dm_stat = dm[["dm_stat"]], p_value = dm[["p_value"]])
  }))
}))))
T$family <- paste(T$market, T$loss); T$p_holm <- ave(T$p_value, T$family, FUN = holm_adjust)
write.csv(S, file.path(QS$paths$tables, "v3_mlp_vs_linear.csv"), row.names = FALSE)
write.csv(T, file.path(QS$paths$tables, "v3_mlp_vs_linear_tests.csv"), row.names = FALSE)
print(S, digits = 4, row.names = FALSE)
print(T[, c("market", "loss", "a", "b", "mean_diff", "ci_lo", "ci_hi", "p_value", "p_holm")], digits = 3, row.names = FALSE)
