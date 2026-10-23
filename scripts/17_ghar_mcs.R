# EXPLORATORY (not pre-registered): stronger classical graph baseline + model confidence set.
# GHAR-style baseline: HAR terms plus the correlation-weighted mean of the one-hop
# neighbours' HAR terms on the SAME daily kNN graph used by the QSW (linear one-hop
# neighbourhood aggregation, the GHAR idea extended by Zhang, Pu, Cucuringu & Dong, IJF 2025).
# Questions: (a) does HAR+QSW(w) beat GHAR? (b) does GHAR+QSW(w) beat GHAR?
# (c) which models survive Hansen's Model Confidence Set (MCS, alpha = 0.10, Tmax)?

for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
ensure_dirs()
prices <- clean_prices(load_market_data())$data
qf <- readRDS(file.path(QS$paths$curated, "qsw_features.rds"))
vt <- readRDS(file.path(QS$paths$curated, "vol_targets.rds"))

ghar_features_market <- function(prices_mk, corr_window = QS$corr_window, k = QS$knn_k, min_obs = 0.8) {
  R <- returns_wide(prices_mk); dates <- as.Date(rownames(R)); tick <- colnames(R)
  R0 <- R; R0[is.na(R0)] <- 0; R2 <- R0^2
  roll <- function(w) apply(R2, 2, function(x) as.numeric(stats::filter(x, rep(1 / w, w), sides = 1)))
  H <- list(d = log(R2 + 1e-8), w = log(roll(5) + 1e-8), m = log(roll(22) + 1e-8))
  rows <- vector("list", length(dates))
  for (t in seq(corr_window + 1, length(dates))) {
    win <- R[(t - corr_window + 1):t, , drop = FALSE]
    ok <- colMeans(!is.na(win)) >= min_obs & !is.na(R[t, ])
    if (sum(ok) < k + 2) next
    g <- knn_graph(suppressWarnings(cor(win[, ok], use = "pairwise.complete.obs")), k)
    A <- g$w / rowSums(g$w)                             # row-normalised one-hop weights
    rows[[t]] <- data.frame(date = dates[t], ticker = tick[ok],
                            gh_d = as.numeric(A %*% H$d[t, ok]), gh_w = as.numeric(A %*% H$w[t, ok]),
                            gh_m = as.numeric(A %*% H$m[t, ok]))
  }
  do.call(rbind, rows)
}
GHAR_COLS <- c(HAR_COLS, "gh_d", "gh_w", "gh_m")
Q_T1 <- c("q_volspill", "q_self", "q_ent")

pd <- file.path(QS$paths$results, "predictions_v2")
res <- list(); mcs_out <- list(); pair <- list()
for (mk in c("NSE", "NASDAQ")) {
  gh <- ghar_features_market(prices[prices$market == mk, ])
  base <- merge(vt, gh, by = c("ticker", "date"))
  qget <- function(o) qf[qf$market == mk & qf$omega == o & qf$graph == "corr", c("ticker", "date", Q_T1)]
  # Common sample for every model so losses are comparable row by row.
  common <- Reduce(function(a, b) merge(a, b[, c("ticker", "date")], by = c("ticker", "date")),
                   list(base, qget(0.25), qget(1)))
  specs <- list(HAR = list(cols = HAR_COLS, o = NA), GHAR = list(cols = GHAR_COLS, o = NA),
                `HAR+QSW w=0.25` = list(cols = c(HAR_COLS, Q_T1), o = 0.25),
                `HAR+QSW w=1` = list(cols = c(HAR_COLS, Q_T1), o = 1),
                `GHAR+QSW w=0.25` = list(cols = c(GHAR_COLS, Q_T1), o = 0.25),
                `GHAR+QSW w=1` = list(cols = c(GHAR_COLS, Q_T1), o = 1))
  losses <- list()
  for (nm in names(specs)) {
    s <- specs[[nm]]
    d <- if (is.na(s$o)) common else merge(common, qget(s$o), by = c("ticker", "date"))
    p <- walk_forward_reg(d, s$cols)
    p$mse <- (p$y - p$pred)^2; p$ql <- qlike(p$y, p$pred)
    losses[[nm]] <- p
    res[[length(res) + 1]] <- data.frame(market = mk, model = nm, n = nrow(p), mse = mean(p$mse),
                                         qlike = mean(p$ql), oos_r2 = 1 - sum(p$mse) / sum((p$y - mean(p$y))^2))
    message(mk, " ", nm, " mse=", round(mean(p$mse), 4))
  }
  for (loss in c("mse", "ql")) {
    L <- Reduce(function(a, b) merge(a, b, by = "date"), lapply(names(losses), function(nm) {
      x <- aggregate(losses[[nm]][[loss]] ~ losses[[nm]]$date, FUN = mean); names(x) <- c("date", nm); x }))
    Lm <- as.matrix(L[, -1])
    m <- MCS::MCSprocedure(Lm, alpha = 0.10, B = 2000, statistic = "Tmax", verbose = FALSE, seed = 1)
    mcs_out[[length(mcs_out) + 1]] <- data.frame(market = mk, loss = ifelse(loss == "ql", "qlike", "mse"),
                                                 model = colnames(Lm), in_mcs_90 = colnames(Lm) %in% rownames(m@show))
    for (cmp in list(c("HAR+QSW w=0.25", "GHAR"), c("GHAR+QSW w=0.25", "GHAR"),
                     c("GHAR+QSW w=0.25", "GHAR+QSW w=1"), c("GHAR", "HAR"))) {
      dm <- dm_test(L[[cmp[1]]], L[[cmp[2]]]); ci <- stationary_boot_ci(L[[cmp[1]]] - L[[cmp[2]]], reps = 1000)
      pair[[length(pair) + 1]] <- data.frame(market = mk, loss = ifelse(loss == "ql", "qlike", "mse"),
                                             a = cmp[1], b = cmp[2], mean_diff = ci[["mean"]], lo = ci[["lo"]],
                                             hi = ci[["hi"]], dm_stat = dm[["dm_stat"]], p_value = dm[["p_value"]])
    }
  }
}
R1 <- do.call(rbind, res); M <- do.call(rbind, mcs_out); P <- do.call(rbind, pair)
write.csv(R1, file.path(QS$paths$tables, "v2_ghar_comparison.csv"), row.names = FALSE)
write.csv(M, file.path(QS$paths$tables, "v2_mcs.csv"), row.names = FALSE)
write.csv(P, file.path(QS$paths$tables, "v2_ghar_pairwise.csv"), row.names = FALSE)
print(R1, digits = 4); print(M); print(P, digits = 3)
