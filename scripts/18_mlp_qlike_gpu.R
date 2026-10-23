# EXPLORATORY: nonlinear forecaster trained with QLIKE on the RTX 4060 (torch/CUDA).
# Motivated by Zhang et al. (IJF 2025): nonlinear spillovers and QLIKE training help.
# Question: do QSW features help once the model is nonlinear and QLIKE-trained?
# Specs (same walk-forward folds, 24-month window, monthly refit, label embargo):
#   GHAR inputs | GHAR + QSW(w = 0.25) | GHAR + QSW(w = 1)
# Model: MLP 2x32 (ReLU), ensemble of 3 seeds, Adam, early stopping on the last 10% of the
# training window (chronological), output = log 5-day variance forecast, QLIKE loss.
#   Rscript scripts/18_mlp_qlike_gpu.R [max_folds]

Sys.setenv(TORCH_CUDATOOLKIT = "FALSE")
suppressPackageStartupMessages(library(torch))
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
source_lines <- readLines("scripts/17_ghar_mcs.R")   # reuse ghar_features_market() definition
eval(parse(text = source_lines[grep("^ghar_features_market", source_lines):(grep("^GHAR_COLS", source_lines) - 1)]))
GHAR_COLS <- c(HAR_COLS, "gh_d", "gh_w", "gh_m"); Q_T1 <- c("q_volspill", "q_self", "q_ent")
max_folds <- as.integer(commandArgs(trailingOnly = TRUE)[1]); if (is.na(max_folds)) max_folds <- Inf
dev <- if (cuda_is_available()) "cuda" else "cpu"; message("device: ", dev)

prices <- clean_prices(load_market_data())$data
qf <- readRDS(file.path(QS$paths$curated, "qsw_features.rds"))
vt <- readRDS(file.path(QS$paths$curated, "vol_targets.rds"))

qlike_t <- function(pred, y) { r <- torch_exp(y - pred); torch_mean(r - (y - pred) - 1) }

fit_mlp <- function(Xtr, ytr, Xte, seed) {
  torch_manual_seed(seed)
  n <- nrow(Xtr); nv <- max(200, floor(0.1 * n)); tr <- 1:(n - nv); va <- (n - nv + 1):n
  X <- torch_tensor(Xtr, dtype = torch_float32(), device = dev); Y <- torch_tensor(ytr, dtype = torch_float32(), device = dev)
  net <- nn_sequential(nn_linear(ncol(Xtr), 32), nn_relu(), nn_linear(32, 32), nn_relu(), nn_linear(32, 1))$to(device = dev)
  opt <- optim_adam(net$parameters, lr = 1e-3, weight_decay = 1e-4)
  best <- Inf; best_state <- NULL; bad <- 0
  for (ep in 1:200) {
    net$train()
    for (b in split(sample(tr), ceiling(seq_along(tr) / 1024))) {
      opt$zero_grad(); l <- qlike_t(net(X[b, ])$squeeze(2), Y[b]); l$backward(); opt$step()
    }
    net$eval()
    vl <- with_no_grad(qlike_t(net(X[va, ])$squeeze(2), Y[va])$item())
    if (vl < best - 1e-5) { best <- vl; best_state <- lapply(net$state_dict(), function(t) t$clone()); bad <- 0 } else bad <- bad + 1
    if (bad >= 10) break
  }
  net$load_state_dict(best_state); net$eval()
  with_no_grad(as.numeric(net(torch_tensor(Xte, dtype = torch_float32(), device = dev))$squeeze(2)$cpu()))
}

out <- list(); t0 <- Sys.time()
for (mk in c("NSE", "NASDAQ")) {
  gh <- ghar_features_market(prices[prices$market == mk, ])
  qget <- function(o) qf[qf$market == mk & qf$omega == o & qf$graph == "corr", c("ticker", "date", Q_T1)]
  base <- Reduce(function(a, b) merge(a, b[, c("ticker", "date")], by = c("ticker", "date")),
                 list(merge(vt, gh, by = c("ticker", "date")), qget(0.25), qget(1)))
  specs <- list(GHAR = list(cols = GHAR_COLS, o = NA), `GHAR+QSW w=0.25` = list(cols = c(GHAR_COLS, Q_T1), o = 0.25),
                `GHAR+QSW w=1` = list(cols = c(GHAR_COLS, Q_T1), o = 1))
  for (nm in names(specs)) {
    s <- specs[[nm]]
    d <- if (is.na(s$o)) base else merge(base, qget(s$o), by = c("ticker", "date"))
    d <- d[complete.cases(d[, c(s$cols, "y_lrv5", "label_date_rv")]), ]; d <- d[order(d$date), ]
    folds <- walk_forward_folds(d$date); folds <- folds[seq_len(min(length(folds), max_folds))]
    for (m in as.list(folds)) {
      sp <- wf_split(d, m, QS$train_months, "label_date_rv")
      if (nrow(sp$train) < QS$min_train_rows || nrow(sp$test) == 0) next
      mu <- colMeans(sp$train[, s$cols]); sdv <- apply(sp$train[, s$cols], 2, sd); sdv[sdv == 0] <- 1
      Xtr <- scale(as.matrix(sp$train[, s$cols]), mu, sdv); Xte <- scale(as.matrix(sp$test[, s$cols]), mu, sdv)
      pred <- rowMeans(sapply(1:3, function(seed) fit_mlp(Xtr, sp$train$y_lrv5, Xte, seed)))
      out[[length(out) + 1]] <- data.frame(market = mk, model = nm, fold = format(m, "%Y-%m"),
                                           date = sp$test$date, ticker = sp$test$ticker, pred = pred, y = sp$test$y_lrv5)
    }
    message(format(Sys.time(), "%H:%M:%S"), " ", mk, " ", nm, " done")
  }
}
P <- do.call(rbind, out); P$mse <- (P$y - P$pred)^2; P$ql <- qlike(P$y, P$pred)
saveRDS(P, file.path(QS$paths$results, "predictions_v2", "mlp_qlike_gpu.rds"))
S <- aggregate(cbind(mse, ql) ~ market + model, P, mean)
pair <- list()
for (mk in unique(P$market)) for (loss in c("mse", "ql")) {
  D <- lapply(split(P[P$market == mk, ], P$model[P$market == mk]), function(x) setNames(aggregate(x[[loss]] ~ x$date, FUN = mean), c("date", "l")))
  for (cmp in list(c("GHAR+QSW w=0.25", "GHAR"), c("GHAR+QSW w=0.25", "GHAR+QSW w=1"))) {
    m <- merge(D[[cmp[1]]], D[[cmp[2]]], by = "date"); dm <- dm_test(m$l.x, m$l.y)
    pair[[length(pair) + 1]] <- data.frame(market = mk, loss = loss, a = cmp[1], b = cmp[2],
                                           mean_diff = mean(m$l.x - m$l.y), dm_stat = dm[["dm_stat"]], p_value = dm[["p_value"]])
  }
}
PP <- do.call(rbind, pair)
suffix <- if (is.finite(max_folds)) "_smoke" else ""
write.csv(S, file.path(QS$paths$tables, paste0("v2_mlp_qlike_gpu", suffix, ".csv")), row.names = FALSE)
write.csv(PP, file.path(QS$paths$tables, paste0("v2_mlp_qlike_gpu_tests", suffix, ".csv")), row.names = FALSE)
message("total ", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), " min on ", dev)
print(S, digits = 4); print(PP, digits = 3)
