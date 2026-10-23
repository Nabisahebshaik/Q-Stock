# Best-effort tuned volatility forecasters with NESTED walk-forward validation.
# For each outer test month m:
#   training window  = [m - 24 months, m), label embargo (label_date_rv < m)
#   inner validation = last 6 months of the training window; inner-train = the 18 months
#                      before it, with embargo label_date_rv < start of validation
#   hyper-parameters are chosen on inner validation (MSE), the model is refit on the full
#   training window, and only then is the test month predicted. The test month is never
#   used for any choice.
# Models:
#   HAR, GHAR (fixed)
#   GHAR+QSW(adaptive w): omega chosen per month from {0,0.1,0.25,0.5,0.75,0.9,1}
#   ENet-all: elastic net on HAR + GHAR + QSW(all omegas); alpha in {0,0.5,1}, lambda on path
#   Combo: equal-weight mean of GHAR, GHAR+QSW(adaptive), ENet-all
# Exploratory relative to the pre-registration; reported in full regardless of outcome.

suppressPackageStartupMessages(library(glmnet))
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
ensure_dirs()
prices <- clean_prices(load_market_data())$data
qf <- readRDS(file.path(QS$paths$curated, "qsw_features.rds"))
vt <- readRDS(file.path(QS$paths$curated, "vol_targets.rds"))
gh_file <- file.path(QS$paths$curated, "ghar_features.rds")
if (!file.exists(gh_file)) saveRDS(do.call(rbind, lapply(c("NSE", "NASDAQ"), function(mk) {
  g <- ghar_features_market(prices[prices$market == mk, ]); g$market <- mk; g })), gh_file)
gh <- readRDS(gh_file)
OMEGAS <- sort(unique(qf$omega[qf$graph == "corr"]))
QC <- c("q_volspill", "q_self", "q_ent")

ols_fit <- function(X, y) { b <- qr.coef(qr(cbind(1, X)), y); b[is.na(b)] <- 0; b }
ols_pred <- function(b, X) as.numeric(cbind(1, X) %*% b)
mse <- function(a, b) mean((a - b)^2)

results <- list(); preds_all <- list(); choices <- list()
for (mk in c("NSE", "NASDAQ")) {
  wide_q <- Reduce(function(a, b) merge(a, b, by = c("ticker", "date")), lapply(OMEGAS, function(o) {
    x <- qf[qf$market == mk & qf$omega == o & qf$graph == "corr", c("ticker", "date", QC)]
    names(x)[3:5] <- paste0(QC, "_", omega_tag(o)); x }))
  d <- merge(merge(vt, gh[gh$market == mk, c("ticker", "date", "gh_d", "gh_w", "gh_m")], by = c("ticker", "date")),
             wide_q, by = c("ticker", "date"))
  qcols <- setdiff(names(wide_q), c("ticker", "date"))
  allc <- c(GHAR_COLS, qcols)
  d <- d[complete.cases(d[, c(allc, "y_lrv5", "label_date_rv")]), ]; d <- d[order(d$date), ]
  for (m in as.list(walk_forward_folds(d$date))) {
    sp <- wf_split(d, m, QS$train_months, "label_date_rv")
    if (nrow(sp$train) < QS$min_train_rows || nrow(sp$test) == 0) next
    vstart <- add_months(m, -6)
    itr <- sp$train[sp$train$date < vstart & sp$train$label_date_rv < vstart, ]
    iva <- sp$train[sp$train$date >= vstart, ]
    tr <- sp$train; te <- sp$test
    M <- function(df, cols) as.matrix(df[, cols, drop = FALSE])

    # fixed baselines
    p_har <- ols_pred(ols_fit(M(tr, HAR_COLS), tr$y_lrv5), M(te, HAR_COLS))
    p_ghar <- ols_pred(ols_fit(M(tr, GHAR_COLS), tr$y_lrv5), M(te, GHAR_COLS))

    # adaptive omega: choose on inner validation
    vloss <- sapply(OMEGAS, function(o) {
      cols <- c(GHAR_COLS, paste0(QC, "_", omega_tag(o)))
      mse(ols_pred(ols_fit(M(itr, cols), itr$y_lrv5), M(iva, cols)), iva$y_lrv5)
    })
    o_star <- OMEGAS[which.min(vloss)]
    cols_star <- c(GHAR_COLS, paste0(QC, "_", omega_tag(o_star)))
    p_adapt <- ols_pred(ols_fit(M(tr, cols_star), tr$y_lrv5), M(te, cols_star))

    # elastic net on everything: choose alpha and lambda on inner validation
    mu <- colMeans(M(itr, allc)); s <- apply(M(itr, allc), 2, sd); s[s == 0] <- 1
    best <- list(loss = Inf)
    for (a in c(0, 0.5, 1)) {
      fit <- glmnet(scale(M(itr, allc), mu, s), itr$y_lrv5, alpha = a, nlambda = 50, standardize = FALSE)
      pv <- predict(fit, scale(M(iva, allc), mu, s))
      l <- colMeans((pv - iva$y_lrv5)^2); j <- which.min(l)
      if (l[j] < best$loss) best <- list(loss = l[j], alpha = a, lambda = fit$lambda[j])
    }
    mu2 <- colMeans(M(tr, allc)); s2 <- apply(M(tr, allc), 2, sd); s2[s2 == 0] <- 1
    fit <- glmnet(scale(M(tr, allc), mu2, s2), tr$y_lrv5, alpha = best$alpha, lambda = best$lambda, standardize = FALSE)
    p_enet <- as.numeric(predict(fit, scale(M(te, allc), mu2, s2)))

    p_combo <- (p_ghar + p_adapt + p_enet) / 3
    preds_all[[length(preds_all) + 1]] <- data.frame(market = mk, fold = format(m, "%Y-%m"), date = te$date,
      ticker = te$ticker, y = te$y_lrv5, HAR = p_har, GHAR = p_ghar, `GHAR+QSW adaptive` = p_adapt,
      `ENet-all` = p_enet, Combo = p_combo, check.names = FALSE)
    choices[[length(choices) + 1]] <- data.frame(market = mk, fold = format(m, "%Y-%m"), omega_star = o_star,
                                                 enet_alpha = best$alpha, enet_lambda = best$lambda)
  }
  message(format(Sys.time(), "%H:%M:%S"), " ", mk, " done")
}
PR <- do.call(rbind, preds_all); CH <- do.call(rbind, choices)
saveRDS(PR, file.path(QS$paths$results, "predictions_v2", "tuned_models.rds"))
models <- c("HAR", "GHAR", "GHAR+QSW adaptive", "ENet-all", "Combo")

summ <- list(); tests <- list()
for (mk in unique(PR$market)) {
  x <- PR[PR$market == mk, ]
  for (md in models) summ[[length(summ) + 1]] <- data.frame(market = mk, model = md, n = nrow(x),
    mse = mean((x$y - x[[md]])^2), qlike = mean(qlike(x$y, x[[md]])),
    oos_r2 = 1 - sum((x$y - x[[md]])^2) / sum((x$y - mean(x$y))^2))
  for (lossname in c("mse", "qlike")) {
    L <- sapply(models, function(md) {
      l <- if (lossname == "mse") (x$y - x[[md]])^2 else qlike(x$y, x[[md]])
      tapply(l, x$date, mean) })
    for (md in setdiff(models, c("HAR", "GHAR"))) for (base in c("GHAR", "HAR")) {
      dlt <- L[, md] - L[, base]; dm <- dm_test(L[, md], L[, base]); ci <- stationary_boot_ci(dlt, reps = 1000)
      tests[[length(tests) + 1]] <- data.frame(market = mk, loss = lossname, model = md, vs = base,
        mean_diff = mean(dlt), ci_lo = ci[["lo"]], ci_hi = ci[["hi"]], dm_stat = dm[["dm_stat"]], p_value = dm[["p_value"]])
    }
  }
}
S <- do.call(rbind, summ); T <- do.call(rbind, tests)
T$family <- paste(T$market, T$loss, T$vs); T$p_holm <- ave(T$p_value, T$family, FUN = holm_adjust)
write.csv(S, file.path(QS$paths$tables, "v3_tuned_models.csv"), row.names = FALSE)
write.csv(T, file.path(QS$paths$tables, "v3_tuned_models_tests.csv"), row.names = FALSE)
write.csv(CH, file.path(QS$paths$tables, "v3_tuned_choices.csv"), row.names = FALSE)
print(S, digits = 4)
print(T[, c("market", "loss", "model", "vs", "mean_diff", "ci_lo", "ci_hi", "p_value", "p_holm")], digits = 3)
print(table(CH$market, CH$omega_star))
