# Stage 4: main comparison (classical vs classical-graph vs DTQW / CTQW /
# fusion / adaptive, +/- sentiment) under chronological walk-forward.
# Run from the project root after 02_build_dataset.R:  Rscript scripts/05_experiments.R

for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
ensure_dirs()
pred_dir <- file.path(QS$paths$results, "predictions"); dir.create(pred_dir, showWarnings = FALSE)

ds <- readRDS(file.path(QS$paths$curated, "dataset_graph.rds"))

# Sentiment is used only if the GDELT download finished for every ticker.
sent_file <- file.path(QS$paths$raw, "sentiment_gdelt_daily.csv")
have_sent <- file.exists(sent_file) &&
  length(unique(read.csv(sent_file)$ticker)) == length(unlist(lapply(QS$universe, names)))
SENT_START <- as.Date("2017-02-01")    # GDELT DOC coverage starts 2017-01-01; allow a 21-day warm-up
if (have_sent) {
  sf <- sentiment_features(ds[, c("ticker", "date")], load_sentiment())
  ds <- merge(ds, sf, by = c("ticker", "date"))
  ds <- ds[order(ds$market, ds$date, ds$ticker), ]
}
cat("sentiment available:", have_sent, "\n")

run_one <- function(data, set_name, model, experiment) {
  cols <- FEATURE_SETS[[set_name]]
  invisible(gc(reset = TRUE))
  t0 <- Sys.time()
  pr <- walk_forward(data, cols, model)
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  g <- gc()
  mem_mb <- sum(g[, 6])   # R heap "max used" (Mb) since reset; excludes ranger's C++ memory
  pr$experiment <- experiment; pr$model <- model; pr$feature_set <- set_name
  saveRDS(pr, file.path(pred_dir, sprintf("%s_%s_%s_%s.rds", experiment, data$market[1], model, set_name)))
  list(pred = pr, secs = secs, mem_mb = mem_mb)
}

summarise_run <- function(pr, base_pr) {
  pm <- prediction_metrics(pr$y_up, pr$p_up)
  sm <- strategy_metrics(backtest(pr))
  a <- daily_logloss(pr); b <- daily_logloss(base_pr)
  ab <- merge(a, b, by = "date", suffixes = c("", "_base"))
  dm <- if (identical(pr$p_up, base_pr$p_up)) c(dm_stat = NA, p_value = NA) else
    dm_test(ab$ll, ab$ll_base)[c("dm_stat", "p_value")]
  c(pm, sm, dm_stat_vs_classical = unname(dm[1]), dm_p_vs_classical = unname(dm[2]))
}

regime_rows <- function(pr) {
  do.call(rbind, lapply(c(0, 1), function(g) {
    s <- pr[!is.na(pr$regime_hi) & pr$regime_hi == g, ]
    data.frame(regime_hi = g, n = nrow(s), auc = auc_score(s$y_up, s$p_up),
               accuracy = mean((s$p_up > 0.5) == s$y_up))
  }))
}

fold_auc <- function(pr) {
  a <- tapply(seq_len(nrow(pr)), pr$fold, function(i) auc_score(pr$y_up[i], pr$p_up[i]))
  c(fold_auc_mean = mean(a, na.rm = TRUE), fold_auc_se = sd(a, na.rm = TRUE) / sqrt(sum(!is.na(a))),
    n_folds = sum(!is.na(a)))
}

experiments <- list(main = list(sets = setdiff(names(FEATURE_SETS), c("classical_sent", "fusion_sent")),
                                start = as.Date("1900-01-01")))
if (have_sent) experiments$sentiment <- list(
  sets = c("classical", "classical_sent", "classical_fusion", "fusion_sent"), start = SENT_START)

# Optional CLI args choose experiments, e.g. `Rscript scripts/05_experiments.R sentiment`.
run_exps <- commandArgs(trailingOnly = TRUE)
if (length(run_exps) == 0) run_exps <- names(experiments)
stopifnot(all(run_exps %in% names(experiments)))

for (ex in run_exps) {
results <- list(); regimes <- list(); costs <- list(); runtime <- list(); foldstats <- list()
for (mk in c("NSE", "NASDAQ")) for (model in c("logit", "rf")) {
  data <- ds[ds$market == mk & ds$date >= experiments[[ex]]$start, ]
  base <- NULL
  for (set_name in experiments[[ex]]$sets) {
    cat(sprintf("[%s] %s %s %s ... ", format(Sys.time(), "%H:%M:%S"), ex, mk, model), set_name, "\n")
    r <- run_one(data, set_name, model, ex)
    if (set_name == "classical") base <- r$pred
    s <- summarise_run(r$pred, base)
    results[[length(results) + 1]] <- data.frame(experiment = ex, market = mk, model = model,
                                                 feature_set = set_name, t(s), check.names = FALSE)
    foldstats[[length(foldstats) + 1]] <- data.frame(experiment = ex, market = mk, model = model,
                                                     feature_set = set_name, t(fold_auc(r$pred)))
    regimes[[length(regimes) + 1]] <- data.frame(experiment = ex, market = mk, model = model,
                                                 feature_set = set_name, regime_rows(r$pred))
    costs[[length(costs) + 1]] <- do.call(rbind, lapply(c(0, 5, 10, 20), function(bps) data.frame(
      experiment = ex, market = mk, model = model, feature_set = set_name, cost_bps = bps,
      sharpe_net = annualized_sharpe(backtest(r$pred, bps)$net))))
    runtime[[length(runtime) + 1]] <- data.frame(experiment = ex, market = mk, model = model,
                                                 feature_set = set_name, n_features = length(FEATURE_SETS[[set_name]]),
                                                 seconds = r$secs, max_mem_mb = r$mem_mb)
  }
}

part_dir <- file.path(QS$paths$tables, "parts"); dir.create(part_dir, showWarnings = FALSE)
cols_out <- c("experiment", "market", "model", "feature_set", "n", "accuracy", "f1", "mcc", "auc",
              "logloss", "sharpe_net", "sharpe_gross", "sharpe_buyhold", "ann_return_net",
              "ann_vol_net", "max_drawdown_net", "avg_exposure", "turnover_cost_ann",
              "dm_stat_vs_classical", "dm_p_vs_classical")
res <- do.call(rbind, results)
write.csv(res[, cols_out], file.path(part_dir, paste0("experiment_results_", ex, ".csv")), row.names = FALSE)
write.csv(do.call(rbind, foldstats), file.path(part_dir, paste0("fold_auc_", ex, ".csv")), row.names = FALSE)
write.csv(do.call(rbind, regimes), file.path(part_dir, paste0("regime_metrics_", ex, ".csv")), row.names = FALSE)
write.csv(do.call(rbind, costs), file.path(part_dir, paste0("cost_sensitivity_", ex, ".csv")), row.names = FALSE)
write.csv(do.call(rbind, runtime), file.path(part_dir, paste0("model_runtime_", ex, ".csv")), row.names = FALSE)
}

# Combine every experiment that has been run so far.
for (tbl in c("experiment_results", "fold_auc", "regime_metrics", "cost_sensitivity", "model_runtime")) {
  fs <- list.files(part_dir, pattern = paste0("^", tbl, "_.*\\.csv$"), full.names = TRUE)
  write.csv(do.call(rbind, lapply(fs, read.csv)), file.path(QS$paths$tables, paste0(tbl, ".csv")),
            row.names = FALSE)
}
res <- read.csv(file.path(QS$paths$tables, "experiment_results.csv"))

# Export a subset of predictions for the Hive `predictions` table.
keep <- c("classical", "classical_dtqw", "classical_ctqw", "classical_fusion")
pf <- list.files(pred_dir, pattern = "^main_.*\\.rds$", full.names = TRUE)
pf <- pf[sub(".*_(logit|rf)_", "", sub("\\.rds$", "", basename(pf))) %in% keep]
pe <- do.call(rbind, lapply(pf, readRDS))
pe <- pe[, c("experiment", "model", "feature_set", "fold", "date", "ticker", "market", "p_up", "y_up", "next_ret")]
pe$date <- format(pe$date)
write.csv(pe, file.path(QS$paths$tables, "predictions_main.csv"), row.names = FALSE, quote = FALSE)

print(res[, c("experiment", "market", "model", "feature_set", "auc", "f1", "sharpe_net", "dm_p_vs_classical")],
      digits = 4)
writeLines(capture.output(sessionInfo()), file.path(QS$paths$results, "stage4_sessionInfo.txt"))
