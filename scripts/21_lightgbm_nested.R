# Nonlinear tuned forecaster: LightGBM with NESTED walk-forward validation (same folds,
# inner validation = last 6 months of each training window, embargo respected).
# Two feature sets, to isolate the QSW contribution in a nonlinear model:
#   LGBM-GHAR      : HAR + GHAR terms
#   LGBM-GHAR+QSW  : + QSW features at all 7 omegas
# Grid (chosen on inner validation MSE): num_leaves {15, 31} x min_data_in_leaf {100, 400};
# learning_rate 0.05, early stopping (50 rounds) on the inner validation set; the full-window
# refit uses the chosen number of rounds. Compared with GHAR (OLS) on the same rows.

suppressPackageStartupMessages(library(lightgbm))
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
qf <- readRDS(file.path(QS$paths$curated, "qsw_features.rds"))
vt <- readRDS(file.path(QS$paths$curated, "vol_targets.rds"))
gh <- readRDS(file.path(QS$paths$curated, "ghar_features.rds"))
OMEGAS <- sort(unique(qf$omega[qf$graph == "corr"])); QC <- c("q_volspill", "q_self", "q_ent")
grid <- expand.grid(num_leaves = c(15, 31), min_data_in_leaf = c(100, 400))
threads <- 6

lgb_fit_pred <- function(Xtr, ytr, Xva, yva, Xte) {
  best <- list(loss = Inf)
  for (g in seq_len(nrow(grid))) {
    p <- list(objective = "regression", learning_rate = 0.05, num_leaves = grid$num_leaves[g],
              min_data_in_leaf = grid$min_data_in_leaf[g], feature_fraction = 0.8, bagging_fraction = 0.8,
              bagging_freq = 1, lambda_l2 = 1, num_threads = threads, verbose = -1, seed = 1)
    dtr <- lgb.Dataset(Xtr, label = ytr); dva <- lgb.Dataset.create.valid(dtr, Xva, label = yva)
    m <- lgb.train(p, dtr, nrounds = 1000, valids = list(va = dva), early_stopping_rounds = 50, verbose = -1)
    if (m$best_score < best$loss) best <- list(loss = m$best_score, params = p, rounds = max(m$best_iter, 10))
  }
  list(params = best$params, rounds = best$rounds)
}

out <- list()
for (mk in c("NSE", "NASDAQ")) {
  wide_q <- Reduce(function(a, b) merge(a, b, by = c("ticker", "date")), lapply(OMEGAS, function(o) {
    x <- qf[qf$market == mk & qf$omega == o & qf$graph == "corr", c("ticker", "date", QC)]
    names(x)[3:5] <- paste0(QC, "_", omega_tag(o)); x }))
  d <- merge(merge(vt, gh[gh$market == mk, c("ticker", "date", "gh_d", "gh_w", "gh_m")], by = c("ticker", "date")),
             wide_q, by = c("ticker", "date"))
  qcols <- setdiff(names(wide_q), c("ticker", "date"))
  d <- d[complete.cases(d[, c(GHAR_COLS, qcols, "y_lrv5", "label_date_rv")]), ]; d <- d[order(d$date), ]
  sets <- list(`LGBM-GHAR` = GHAR_COLS, `LGBM-GHAR+QSW` = c(GHAR_COLS, qcols))
  for (m in as.list(walk_forward_folds(d$date))) {
    sp <- wf_split(d, m, QS$train_months, "label_date_rv")
    if (nrow(sp$train) < QS$min_train_rows || nrow(sp$test) == 0) next
    vstart <- add_months(m, -6)
    itr <- sp$train[sp$train$date < vstart & sp$train$label_date_rv < vstart, ]; iva <- sp$train[sp$train$date >= vstart, ]
    b <- qr.coef(qr(cbind(1, as.matrix(sp$train[, GHAR_COLS]))), sp$train$y_lrv5); b[is.na(b)] <- 0
    row <- data.frame(market = mk, fold = format(m, "%Y-%m"), date = sp$test$date, ticker = sp$test$ticker,
                      y = sp$test$y_lrv5, GHAR = as.numeric(cbind(1, as.matrix(sp$test[, GHAR_COLS])) %*% b), check.names = FALSE)
    for (nm in names(sets)) {
      cols <- sets[[nm]]
      ch <- lgb_fit_pred(as.matrix(itr[, cols]), itr$y_lrv5, as.matrix(iva[, cols]), iva$y_lrv5)
      mfull <- lgb.train(ch$params, lgb.Dataset(as.matrix(sp$train[, cols]), label = sp$train$y_lrv5),
                         nrounds = ch$rounds, verbose = -1)
      row[[nm]] <- predict(mfull, as.matrix(sp$test[, cols]))
    }
    out[[length(out) + 1]] <- row
  }
  message(format(Sys.time(), "%H:%M:%S"), " ", mk, " done")
}
PR <- do.call(rbind, out)
saveRDS(PR, file.path(QS$paths$results, "predictions_v2", "lightgbm_nested.rds"))
models <- c("GHAR", "LGBM-GHAR", "LGBM-GHAR+QSW")
S <- do.call(rbind, lapply(split(PR, PR$market), function(x) do.call(rbind, lapply(models, function(md)
  data.frame(market = x$market[1], model = md, mse = mean((x$y - x[[md]])^2), qlike = mean(qlike(x$y, x[[md]])),
             oos_r2 = 1 - sum((x$y - x[[md]])^2) / sum((x$y - mean(x$y))^2))))))
Tt <- do.call(rbind, lapply(split(PR, PR$market), function(x) do.call(rbind, lapply(c("mse", "qlike"), function(ls) {
  L <- sapply(models, function(md) tapply(if (ls == "mse") (x$y - x[[md]])^2 else qlike(x$y, x[[md]]), x$date, mean))
  do.call(rbind, lapply(list(c("LGBM-GHAR", "GHAR"), c("LGBM-GHAR+QSW", "GHAR"), c("LGBM-GHAR+QSW", "LGBM-GHAR")), function(cp) {
    dm <- dm_test(L[, cp[1]], L[, cp[2]])
    data.frame(market = x$market[1], loss = ls, a = cp[1], b = cp[2], mean_diff = mean(L[, cp[1]] - L[, cp[2]]),
               dm_stat = dm[["dm_stat"]], p_value = dm[["p_value"]]) })) }))))
write.csv(S, file.path(QS$paths$tables, "v3_lightgbm.csv"), row.names = FALSE)
write.csv(Tt, file.path(QS$paths$tables, "v3_lightgbm_tests.csv"), row.names = FALSE)
print(S, digits = 5, row.names = FALSE); print(Tt, digits = 3, row.names = FALSE)
