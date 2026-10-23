# Positive control / power analysis: can the evaluation pipeline detect a real signal?
# A synthetic feature s = b * z(next_ret) + noise (noise ~ N(0,1)) is added to the classical
# features; b sets its strength. With b = 0 it is pure noise (negative control).
# For each b and market: walk-forward logistic regression, AUC, and the DM test vs classical
# features only. Repeated over 5 noise seeds; detection = DM p < 0.05 with lower loss.
# This bounds the smallest effect the protocol can detect, so the null results can be read.
# Note: the signal deliberately uses the label (that is the point of a positive control).

for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
ds <- readRDS(file.path(QS$paths$curated, "dataset_graph.rds"))
strengths <- c(0, 0.01, 0.02, 0.03, 0.05, 0.1)
rows <- list()
for (mk in c("NSE", "NASDAQ")) {
  d <- ds[ds$market == mk, c("ticker", "date", "market", CLASSICAL_COLS, "y_up", "next_ret", "label_date")]
  base <- walk_forward(d, CLASSICAL_COLS, "logit"); bl <- daily_logloss(base)
  z <- (d$next_ret - mean(d$next_ret, na.rm = TRUE)) / sd(d$next_ret, na.rm = TRUE)
  for (b in strengths) for (seed in 1:5) {
    set.seed(seed)
    d$sig <- b * z + rnorm(nrow(d))
    pr <- walk_forward(d, c(CLASSICAL_COLS, "sig"), "logit")
    m <- merge(daily_logloss(pr), bl, by = "date", suffixes = c("", "_base"))
    dm <- dm_test(m$ll, m$ll_base)
    rows[[length(rows) + 1]] <- data.frame(market = mk, strength = b, seed = seed,
      signal_corr_with_return = suppressWarnings(cor(d$sig, d$next_ret, use = "complete.obs")),
      auc = auc_score(pr$y_up, pr$p_up), auc_base = auc_score(base$y_up, base$p_up),
      dm_stat = dm[["dm_stat"]], p_value = dm[["p_value"]],
      detected = dm[["p_value"]] < 0.05 && dm[["mean_diff"]] < 0)
    message(mk, " b=", b, " seed=", seed, " auc=", round(tail(rows, 1)[[1]]$auc, 4), " p=", signif(dm[["p_value"]], 3))
  }
}
pw <- do.call(rbind, rows)
write.csv(pw, file.path(QS$paths$tables, "power_analysis.csv"), row.names = FALSE)
s <- aggregate(cbind(signal_corr_with_return, auc, detected) ~ market + strength, pw, mean)
names(s)[names(s) == "detected"] <- "detection_rate"
write.csv(s, file.path(QS$paths$tables, "power_analysis_summary.csv"), row.names = FALSE)
print(s, digits = 3)
