# v2 confirmatory experiments (see docs/preregistration_v2.md).
#   T1 (primary): 5-day-ahead log realised variance; OLS; HAR-RV baseline.
#   T2: next-day direction; logistic regression; classical baseline.
#   T3: cross-sectional rank IC of the T2 scores.
# Hypotheses: H1 (graph helps T1), H2 (some omega < 1 beats omega = 1, Holm over 6),
# H3 (random graph does not reproduce H1).
# Run after 02_build_dataset.R and 10_qsw_features.R.

for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
ensure_dirs()
pred_dir <- file.path(QS$paths$results, "predictions_v2"); dir.create(pred_dir, showWarnings = FALSE)

qf <- readRDS(file.path(QS$paths$curated, "qsw_features.rds"))
vt <- readRDS(file.path(QS$paths$curated, "vol_targets.rds"))
ds <- readRDS(file.path(QS$paths$curated, "dataset_graph.rds"))
OMEGAS <- sort(unique(qf$omega[qf$graph == "corr"]))
Q_T1 <- c("q_volspill", "q_self", "q_ent")
Q_T2 <- c("q_self", "q_mom", "q_ent")

variants <- c(list(list(name = "baseline", omega = NA, graph = NA)),
              lapply(OMEGAS, function(o) list(name = paste0("qsw_", omega_tag(o)), omega = o, graph = "corr")),
              lapply(c(0, 1), function(o) list(name = paste0("random_", omega_tag(o)), omega = o, graph = "random")))

daily_mean <- function(pr, loss) aggregate(loss ~ date, data.frame(date = pr$date, loss = loss), mean)
dm_pair <- function(a, b) {   # a, b: data.frames(date, loss); returns DM stat, p, mean diff (a - b)
  m <- merge(a, b, by = "date", suffixes = c("_a", "_b"))
  c(dm_test(m$loss_a, m$loss_b), n_days = nrow(m))
}
boot_pair <- function(a, b) {
  m <- merge(a, b, by = "date", suffixes = c("_a", "_b"))
  stationary_boot_ci(m$loss_a - m$loss_b, reps = 1000)
}

t1 <- list(); t1_loss <- list(); t2 <- list(); t2_loss <- list(); t2_pred <- list()
for (mk in c("NSE", "NASDAQ")) {
  tick_mk <- unique(ds$ticker[ds$market == mk])
  vt_mk <- vt[vt$ticker %in% tick_mk, ]
  cls_mk <- ds[ds$market == mk, c("ticker", "date", "market", CLASSICAL_COLS, "y_up", "next_ret", "label_date")]
  for (v in variants) {
    if (v$name == "baseline") {
      d1 <- vt_mk; cols1 <- HAR_COLS
      d2 <- cls_mk; cols2 <- CLASSICAL_COLS
    } else {
      q <- qf[qf$market == mk & qf$omega == v$omega & qf$graph == v$graph, c("ticker", "date", Q_T1, "q_mom")]
      d1 <- merge(vt_mk, q, by = c("ticker", "date")); cols1 <- c(HAR_COLS, Q_T1)
      d2 <- merge(cls_mk, q, by = c("ticker", "date")); cols2 <- c(CLASSICAL_COLS, Q_T2)
    }
    message(format(Sys.time(), "%H:%M:%S"), " ", mk, " ", v$name)
    # T1: realised volatility
    p1 <- walk_forward_reg(d1, cols1)
    saveRDS(p1, file.path(pred_dir, sprintf("T1_%s_%s.rds", mk, v$name)))
    mse <- (p1$y - p1$pred)^2; ql <- qlike(p1$y, p1$pred)
    t1_loss[[paste(mk, v$name)]] <- list(mse = daily_mean(p1, mse), qlike = daily_mean(p1, ql))
    t1[[length(t1) + 1]] <- data.frame(market = mk, variant = v$name, omega = v$omega, graph = v$graph,
                                       n = nrow(p1), mse = mean(mse), qlike = mean(ql),
                                       oos_r2 = 1 - sum(mse) / sum((p1$y - mean(p1$y))^2))
    # T2: direction (+ T3 rank IC)
    p2 <- walk_forward(d2, cols2, "logit")
    saveRDS(p2, file.path(pred_dir, sprintf("T2_%s_%s.rds", mk, v$name)))
    pm <- prediction_metrics(p2$y_up, p2$p_up); ic <- rank_ic(p2)
    t2_loss[[paste(mk, v$name)]] <- daily_logloss(p2)
    names(t2_loss[[paste(mk, v$name)]])[2] <- "loss"
    t2[[length(t2) + 1]] <- data.frame(market = mk, variant = v$name, omega = v$omega, graph = v$graph,
                                       t(pm), t(ic), sharpe_net = annualized_sharpe(backtest(p2)$net))
  }
}
T1 <- do.call(rbind, t1); T2 <- do.call(rbind, t2)

# ---- Hypothesis tests ----
tests <- list()
add_test <- function(hyp, target, loss, mk, a, b, lst) {
  la <- lst[[paste(mk, a)]]; lb <- lst[[paste(mk, b)]]
  if (!is.null(loss)) { la <- la[[loss]]; lb <- lb[[loss]] }
  dm <- dm_pair(la, lb); ci <- boot_pair(la, lb)
  data.frame(hypothesis = hyp, target = target, loss = ifelse(is.null(loss), "logloss", loss), market = mk,
             model_a = a, model_b = b, mean_diff_a_minus_b = dm[["mean_diff"]], ci_lo = ci[["lo"]],
             ci_hi = ci[["hi"]], dm_stat = dm[["dm_stat"]], p_value = dm[["p_value"]], n_days = dm[["n_days"]])
}
qnames <- paste0("qsw_", omega_tag(OMEGAS))
for (mk in c("NSE", "NASDAQ")) {
  for (loss in c("mse", "qlike")) {
    for (q in qnames) tests[[length(tests) + 1]] <- add_test("H1", "T1", loss, mk, q, "baseline", t1_loss)
    for (q in setdiff(qnames, "qsw_w100")) tests[[length(tests) + 1]] <- add_test("H2", "T1", loss, mk, q, "qsw_w100", t1_loss)
    for (r in c("random_w000", "random_w100")) tests[[length(tests) + 1]] <- add_test("H3", "T1", loss, mk, r, "baseline", t1_loss)
  }
  for (q in qnames) tests[[length(tests) + 1]] <- add_test("T2_vs_classical", "T2", NULL, mk, q, "baseline", t2_loss)
  for (q in setdiff(qnames, "qsw_w100")) tests[[length(tests) + 1]] <- add_test("T2_H2", "T2", NULL, mk, q, "qsw_w100", t2_loss)
}
TT <- do.call(rbind, tests)
# Holm within each pre-registered family (hypothesis x target x loss x market).
TT$family <- paste(TT$hypothesis, TT$target, TT$loss, TT$market)
TT$p_holm <- ave(TT$p_value, TT$family, FUN = holm_adjust)
TT$p_bh_all <- bh_adjust(TT$p_value)

write.csv(T1, file.path(QS$paths$tables, "v2_T1_volatility.csv"), row.names = FALSE)
write.csv(T2, file.path(QS$paths$tables, "v2_T2_direction.csv"), row.names = FALSE)
write.csv(TT, file.path(QS$paths$tables, "v2_hypothesis_tests.csv"), row.names = FALSE)
print(T1, digits = 4); print(T2[, c("market", "variant", "auc", "logloss", "mean_ic", "nw_t", "sharpe_net")], digits = 4)
print(TT[, c("hypothesis", "loss", "market", "model_a", "model_b", "mean_diff_a_minus_b", "ci_lo", "ci_hi", "p_value", "p_holm")], digits = 3)
