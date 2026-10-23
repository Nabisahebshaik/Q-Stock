# Explainability (Brief 1, Phase 5): exact SHAP values for the linear models.
# For a linear model f(x) = b0 + sum_j b_j x_j with independent-feature SHAP,
# phi_j(x) = b_j (x_j - E_train[x_j]) exactly; no sampling approximation needed.
# Refits the same walk-forward folds, then aggregates mean |phi| by feature group
# and by the past-only volatility regime (regime_hi from 02_build_dataset.R).

suppressPackageStartupMessages(library(ggplot2))
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
ensure_dirs()
qf <- readRDS(file.path(QS$paths$curated, "qsw_features.rds"))
vt <- readRDS(file.path(QS$paths$curated, "vol_targets.rds"))
ds <- readRDS(file.path(QS$paths$curated, "dataset_graph.rds"))
OMEGA <- 0.25   # best NASDAQ omega in the pre-registered grid; reported for both markets

linear_shap_wf <- function(data, cols, target, label_col, logistic = FALSE) {
  data <- data[complete.cases(data[, c(cols, target, label_col, "regime_hi")]), ]
  out <- list()
  for (m in as.list(walk_forward_folds(data$date))) {
    sp <- wf_split(data, m, QS$train_months, label_col)
    if (nrow(sp$train) < QS$min_train_rows || nrow(sp$test) == 0) next
    mu <- colMeans(sp$train[, cols]); s <- apply(sp$train[, cols], 2, sd); s[s == 0] <- 1
    X <- scale(as.matrix(sp$train[, cols]), mu, s); Xt <- scale(as.matrix(sp$test[, cols]), mu, s)
    b <- if (logistic) suppressWarnings(glm.fit(cbind(1, X), sp$train[[target]], family = binomial()))$coefficients
         else qr.coef(qr(cbind(1, X)), sp$train[[target]])
    b[is.na(b)] <- 0
    phi <- sweep(Xt, 2, b[-1], `*`)          # standardised x has train mean 0, so phi_j = b_j * x_j
    out[[length(out) + 1]] <- data.frame(date = sp$test$date, regime_hi = sp$test$regime_hi, phi)
  }
  do.call(rbind, out)
}

res <- list()
for (mk in c("NSE", "NASDAQ")) {
  base <- ds[ds$market == mk, c("ticker", "date", "regime_hi", CLASSICAL_COLS, "y_up", "label_date")]
  q <- qf[qf$market == mk & qf$omega == OMEGA & qf$graph == "corr", c("ticker", "date", "q_volspill", "q_self", "q_ent", "q_mom")]
  d1 <- merge(merge(vt, q, by = c("ticker", "date")), base[, c("ticker", "date", "regime_hi")], by = c("ticker", "date"))
  d2 <- merge(base, q, by = c("ticker", "date"))
  for (task in c("T1_volatility", "T2_direction")) {
    sh <- if (task == "T1_volatility")
      linear_shap_wf(d1, c(HAR_COLS, "q_volspill", "q_self", "q_ent"), "y_lrv5", "label_date_rv")
    else linear_shap_wf(d2, c(CLASSICAL_COLS, "q_self", "q_mom", "q_ent"), "y_up", "label_date", logistic = TRUE)
    feats <- setdiff(names(sh), c("date", "regime_hi"))
    for (rg in c(0, 1)) {
      a <- colMeans(abs(sh[sh$regime_hi == rg, feats]))
      res[[length(res) + 1]] <- data.frame(market = mk, task = task, regime = ifelse(rg == 1, "high-vol", "low-vol"),
                                           feature = feats, mean_abs_shap = a,
                                           group = ifelse(grepl("^q_", feats), "QSW (omega = 0.25)",
                                                          ifelse(task == "T1_volatility", "HAR-RV", "classical")))
    }
  }
}
ex <- do.call(rbind, res); rownames(ex) <- NULL
ex$share_within_task <- ave(ex$mean_abs_shap, ex$market, ex$task, ex$regime, FUN = function(x) x / sum(x))
write.csv(ex, file.path(QS$paths$tables, "explainability_shap.csv"), row.names = FALSE)
grp <- aggregate(share_within_task ~ market + task + regime + group, ex, sum)
write.csv(grp, file.path(QS$paths$tables, "explainability_shap_groups.csv"), row.names = FALSE)
print(grp, digits = 3)

p <- ggplot(ex, aes(reorder(feature, mean_abs_shap), mean_abs_shap, fill = regime)) +
  geom_col(position = position_dodge(width = 0.75), width = 0.7) + coord_flip() +
  facet_grid(task ~ market, scales = "free") +
  scale_fill_manual(values = c("high-vol" = "#eb6834", "low-vol" = "#2a78d6"), name = NULL) +
  labs(x = NULL, y = "Mean |SHAP| (exact, linear model; standardised features)",
       title = "What drives the forecasts: HAR/classical vs quantum-stochastic-walk features",
       caption = "QSW at omega = 0.25. Regime = market mean 20-day vol above its trailing 250-day median (past-only).") +
  theme_minimal(base_size = 10) + theme(legend.position = "top", plot.background = element_rect(fill = "#fcfcfb", colour = NA))
ggsave(file.path(QS$paths$figures, "fig9_explainability_shap.png"), p, width = 10, height = 7, dpi = 300, bg = "#fcfcfb")
