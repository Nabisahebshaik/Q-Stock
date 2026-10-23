# Stage 4: ablations (logistic regression, walk-forward, both markets).
#   A. Walk hyper-parameters, one at a time around the defaults in R/config.R:
#      steps (DTQW/RW), tau_max (CTQW/heat), kNN k, correlation window.
#   B. Random-graph control: same pipeline on random "correlations".
#   C. Drop-one feature ablation inside the DTQW+CTQW fusion set.
# Run from the project root after 02_build_dataset.R.

for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
ensure_dirs()
prices <- clean_prices(load_market_data())$data
base_ds <- readRDS(file.path(QS$paths$curated, "dataset_graph.rds"))

SETS <- c("classical", "classical_rw", "classical_heat", "classical_dtqw", "classical_ctqw", "classical_fusion")
eval_sets <- function(ds, label, param, value, sets = SETS, extra_sets = list()) {
  out <- list()
  all_sets <- c(FEATURE_SETS[sets], extra_sets)
  for (mk in c("NSE", "NASDAQ")) {
    d <- ds[ds$market == mk, ]
    base <- walk_forward(d, FEATURE_SETS$classical, "logit")
    bl <- daily_logloss(base)
    for (s in names(all_sets)) {
      pr <- if (s == "classical") base else walk_forward(d, all_sets[[s]], "logit")
      ab <- merge(daily_logloss(pr), bl, by = "date", suffixes = c("", "_base"))
      dm <- if (s == "classical") c(dm_stat = NA, p_value = NA) else dm_test(ab$ll, ab$ll_base)
      pm <- prediction_metrics(pr$y_up, pr$p_up)
      out[[length(out) + 1]] <- data.frame(
        ablation = label, param = param, value = value, market = mk, feature_set = s,
        auc = pm[["auc"]], logloss = pm[["logloss"]], f1 = pm[["f1"]],
        sharpe_net = annualized_sharpe(backtest(pr)$net),
        dm_stat_vs_classical = dm[["dm_stat"]], dm_p_vs_classical = dm[["p_value"]])
    }
  }
  r <- do.call(rbind, out); print(r[, c("param", "value", "market", "feature_set", "auc", "dm_p_vs_classical")], digits = 4)
  r
}

res <- list()
res[[1]] <- eval_sets(base_ds, "default", "default", "default")

grid <- list(steps = c(3, 5, 20), tau_max = c(0.5, 1, 4), k = c(3, 6), corr_window = c(40, 120))
for (p in names(grid)) for (v in grid[[p]]) {
  message("ablation ", p, " = ", v)
  t0 <- Sys.time()
  ds <- build_dataset(prices, graph_args = setNames(list(v), p))
  message("  features built in ", round(as.numeric(difftime(Sys.time(), t0, units = "secs"))), " s")
  # steps only affects rw/dtqw; tau_max only heat/ctqw. Evaluate all for simplicity.
  res[[length(res) + 1]] <- eval_sets(ds, "hyperparameter", p, as.character(v))
}

message("random-graph control")
ds_rand <- build_dataset(prices, graph_args = list(graph = "random"))
res[[length(res) + 1]] <- eval_sets(ds_rand, "random_graph", "graph", "random")

message("drop-one feature ablation")
fusion <- FEATURE_SETS$classical_fusion
drop_sets <- setNames(lapply(c(graph_cols("dtqw"), graph_cols("ctqw")), function(c) setdiff(fusion, c)),
                      paste0("fusion_minus_", c(graph_cols("dtqw"), graph_cols("ctqw"))))
res[[length(res) + 1]] <- eval_sets(base_ds, "drop_one", "dropped", "see feature_set",
                                    sets = c("classical", "classical_fusion"), extra_sets = drop_sets)

ab <- do.call(rbind, res)
write.csv(ab, file.path(QS$paths$tables, "ablation_results.csv"), row.names = FALSE)
