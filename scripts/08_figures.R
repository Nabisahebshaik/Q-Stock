# Research figures (PNG, 300 dpi) and markdown tables from results/tables/*.csv.
# Run from the project root after 05-07.

suppressPackageStartupMessages(library(ggplot2))
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
ensure_dirs()
tb <- function(x) file.path(QS$paths$tables, x)
fig <- function(name, p, w = 8, h = 5) {
  ggsave(file.path(QS$paths$figures, name), p, width = w, height = h, dpi = 300, bg = "#fcfcfb")
  message("wrote ", name)
}

# Categorical slots in fixed order (validated reference palette, light mode).
PAL <- c("#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#6250d6", "#e34948")
theme_qs <- theme_minimal(base_size = 11) +
  theme(plot.background = element_rect(fill = "#fcfcfb", colour = NA),
        text = element_text(colour = "#0b0b0b"), axis.text = element_text(colour = "#52514e"),
        panel.grid.minor = element_blank(), panel.grid.major = element_line(colour = "#e6e5e1", linewidth = 0.3),
        legend.position = "top", plot.title.position = "plot",
        plot.caption = element_text(colour = "#52514e", hjust = 0))

SET_ORDER <- c("classical", "classical_rw", "classical_heat", "classical_ppr", "classical_dtqw",
               "classical_ctqw", "classical_fusion", "classical_adaptive", "classical_sent", "fusion_sent")

md_table <- function(df, file, digits = 4) {
  df[] <- lapply(df, function(x) if (is.numeric(x)) signif(x, digits) else x)
  lines <- c(paste("|", paste(names(df), collapse = " | "), "|"),
             paste("|", paste(rep("---", ncol(df)), collapse = " | "), "|"),
             apply(df, 1, function(r) paste("|", paste(r, collapse = " | "), "|")))
  writeLines(lines, file.path(QS$paths$tables, file))
}

# ---- Fig 1: fold-level AUC by feature set (mean +/- 95% CI across monthly folds) ----
if (file.exists(tb("fold_auc.csv"))) {
  fa <- read.csv(tb("fold_auc.csv"))
  fa <- fa[fa$experiment == "main", ]
  fa$feature_set <- factor(fa$feature_set, levels = rev(intersect(SET_ORDER, fa$feature_set)))
  fa$model <- factor(fa$model, levels = c("logit", "rf"), labels = c("Logistic regression", "Random forest"))
  p <- ggplot(fa, aes(fold_auc_mean, feature_set, colour = model, shape = model)) +
    geom_vline(xintercept = 0.5, colour = "#8a8984", linewidth = 0.4, linetype = 2) +
    geom_errorbar(aes(xmin = fold_auc_mean - 1.96 * fold_auc_se, xmax = fold_auc_mean + 1.96 * fold_auc_se),
                  width = 0, linewidth = 0.6, orientation = "y", position = position_dodge(width = 0.6)) +
    geom_point(size = 2.4, position = position_dodge(width = 0.6)) +
    facet_wrap(~market) + scale_colour_manual(values = PAL[1:2], name = NULL) +
    scale_shape_manual(values = c(16, 17), name = NULL) +
    labs(x = "Out-of-sample AUC (mean of monthly folds, 95% CI)", y = NULL,
         title = "Next-day direction: AUC by feature set",
         caption = "Chronological walk-forward, 24-month rolling training window, 1-month test folds. Dashed line = chance.") +
    theme_qs
  fig("fig1_auc_by_feature_set.png", p, 9, 5.5)
}

# ---- Fig 2: net equity curves (logistic regression) ----
pred_dir <- file.path(QS$paths$results, "predictions")
eq_sets <- c(classical = "Classical", classical_fusion = "Classical + DTQW + CTQW")
eq <- do.call(rbind, lapply(c("NSE", "NASDAQ"), function(mk) {
  parts <- lapply(names(eq_sets), function(s) {
    f <- file.path(pred_dir, sprintf("main_%s_logit_%s.rds", mk, s))
    if (!file.exists(f)) return(NULL)
    d <- backtest(readRDS(f))
    rbind(data.frame(market = mk, date = d$date, series = eq_sets[[s]], equity = cumprod(1 + d$net)),
          if (s == "classical") data.frame(market = mk, date = d$date, series = "Buy & hold (equal weight)",
                                          equity = cumprod(1 + d$bh)))
  })
  do.call(rbind, parts)
}))
if (!is.null(eq) && nrow(eq)) {
  eq$series <- factor(eq$series, levels = c("Buy & hold (equal weight)", "Classical", "Classical + DTQW + CTQW"))
  p <- ggplot(eq, aes(date, equity, colour = series)) + geom_line(linewidth = 0.6) +
    facet_wrap(~market, scales = "free_y") + scale_y_log10() +
    scale_colour_manual(values = PAL[c(3, 1, 2)], name = NULL) +
    labs(x = NULL, y = "Growth of 1 (log scale)", title = "Long/flat strategy equity, net of 10 bps one-way costs",
         caption = "Logistic regression; position = 1 if p(up) > 0.5. Survivorship bias: universe = today's large caps.") +
    theme_qs
  fig("fig2_equity_curves.png", p, 9, 4.5)
}

# ---- Fig 3: hyper-parameter ablations ----
if (file.exists(tb("ablation_results.csv"))) {
  ab <- read.csv(tb("ablation_results.csv"))
  hp <- ab[ab$ablation == "hyperparameter" | ab$ablation == "default", ]
  defaults <- c(steps = QS$walk_steps, tau_max = QS$walk_time, k = QS$knn_k, corr_window = QS$corr_window)
  hp <- do.call(rbind, c(list(hp[hp$ablation == "hyperparameter", ]), lapply(names(defaults), function(p) {
    d <- hp[hp$ablation == "default", ]; d$param <- p; d$value <- defaults[[p]]; d })))
  hp$value <- as.numeric(hp$value)
  hp <- hp[hp$feature_set %in% c("classical_rw", "classical_heat", "classical_dtqw", "classical_ctqw"), ]
  hp$feature_set <- factor(hp$feature_set, levels = c("classical_rw", "classical_heat", "classical_dtqw", "classical_ctqw"),
                           labels = c("Random walk", "Heat kernel", "DTQW", "CTQW"))
  base_auc <- ab[ab$ablation == "default" & ab$feature_set == "classical", c("market", "auc")]
  p <- ggplot(hp, aes(value, auc, colour = feature_set, shape = feature_set)) +
    geom_hline(data = base_auc, aes(yintercept = auc), colour = "#8a8984", linetype = 2, linewidth = 0.4) +
    geom_line(linewidth = 0.5) + geom_point(size = 2.2) +
    facet_grid(market ~ param, scales = "free_x") +
    scale_colour_manual(values = PAL[1:4], name = NULL) + scale_shape_manual(values = c(16, 17, 15, 18), name = NULL) +
    labs(x = "Parameter value", y = "Out-of-sample AUC",
         title = "Sensitivity to walk hyper-parameters (logistic regression)",
         caption = "Dashed line = classical features only.") + theme_qs
  fig("fig3_ablation_hyperparameters.png", p, 10, 5.5)
  md_table(ab[, c("ablation", "param", "value", "market", "feature_set", "auc", "logloss", "sharpe_net",
                  "dm_p_vs_classical")], "ablation_results.md")
}

# ---- Fig 4: simulation scalability ----
if (file.exists(tb("qw_scalability.csv"))) {
  sc <- read.csv(tb("qw_scalability.csv"))
  sc$method <- factor(sc$method, levels = c("classical_rw", "ctqw_eigen", "dtqw_sparse", "dtqw_dense"),
                      labels = c("Classical RW (dense)", "CTQW (eigendecomposition)", "DTQW (sparse)", "DTQW (dense)"))
  long <- rbind(data.frame(sc, metric = "Median runtime (s)", value = sc$median_seconds),
                data.frame(sc, metric = "R heap allocated (MB)", value = sc$mem_alloc_mb))
  p <- ggplot(long, aes(n_nodes, value, colour = method, shape = method)) + geom_line(linewidth = 0.5) +
    geom_point(size = 2.2) + scale_x_log10() + scale_y_log10() + facet_wrap(~metric, scales = "free_y") +
    scale_colour_manual(values = PAL[1:4], name = NULL) + scale_shape_manual(values = c(16, 17, 15, 18), name = NULL) +
    labs(x = "Graph size N (nodes)", y = NULL, title = "Classical simulation cost vs graph size (all N start nodes)",
         caption = "Random kNN graphs (k = 4), 10 walk steps / 10 time points. CPU, reference BLAS.") + theme_qs
  fig("fig4_scalability.png", p, 10, 4.5)
  md_table(sc, "qw_scalability.md")
}

# ---- Fig 5: Spark vs base R ----
if (file.exists(tb("spark_scaling.csv"))) {
  ss <- read.csv(tb("spark_scaling.csv"))
  sl <- rbind(data.frame(rows = ss$rows, engine = "Spark 3.5 local[8] (sparklyr)", seconds = ss$spark_seconds),
              data.frame(rows = ss$rows, engine = "Base R (single thread)", seconds = ss$base_r_seconds))
  sl <- sl[!is.na(sl$seconds), ]
  p <- ggplot(sl, aes(rows, seconds, colour = engine, shape = engine)) + geom_line(linewidth = 0.5) +
    geom_point(size = 2.4) + scale_x_log10(labels = scales::label_comma()) + scale_y_log10() +
    scale_colour_manual(values = PAL[1:2], name = NULL) + scale_shape_manual(values = c(16, 17), name = NULL) +
    labs(x = "Rows (price table replicated)", y = "Seconds", title = "Rolling-feature computation: Spark vs base R") +
    theme_qs
  fig("fig5_spark_vs_r.png", p, 7, 4.5)
  md_table(ss, "spark_scaling.md")
}

# ---- Fig 6: walk distributions on one real market graph ----
prices <- clean_prices(load_market_data())$data
pm <- prices[prices$market == "NASDAQ", ]
R <- returns_wide(pm); t_end <- nrow(R)
rho <- cor(R[(t_end - QS$corr_window + 1):t_end, ], use = "pairwise.complete.obs")
g <- knn_graph(rho, QS$knn_k)
Ps <- walk_distributions(g$adj, g$w, QS$walk_steps, QS$walk_time, QS$ppr_alpha)
start <- which(colnames(R) == "NVDA")
dist <- do.call(rbind, lapply(c("rw", "heat", "dtqw", "ctqw"), function(m)
  data.frame(method = m, ticker = colnames(R), p = Ps[[m]][start, ])))
dist$method <- factor(dist$method, levels = c("rw", "heat", "dtqw", "ctqw"),
                      labels = c("Classical RW", "Heat kernel", "DTQW", "CTQW"))
dist$ticker <- factor(dist$ticker, levels = colnames(R)[order(-Ps$rw[start, ])])
p <- ggplot(dist, aes(ticker, p)) + geom_col(fill = PAL[1], width = 0.7) + facet_wrap(~method, ncol = 1) +
  labs(x = NULL, y = "Time-averaged probability", title = sprintf(
    "Walks started at NVDA on the NASDAQ kNN correlation graph (%s)", rownames(R)[t_end])) +
  theme_qs + theme(axis.text.x = element_text(angle = 60, hjust = 1, size = 8))
fig("fig6_walk_distributions.png", p, 9, 7)

# ---- Markdown versions of the main tables ----
if (file.exists(tb("experiment_results.csv"))) {
  er <- read.csv(tb("experiment_results.csv"))
  md_table(er[, c("experiment", "market", "model", "feature_set", "n", "accuracy", "f1", "mcc", "auc",
                  "logloss", "sharpe_net", "sharpe_buyhold", "max_drawdown_net", "dm_p_vs_classical")],
           "experiment_results.md")
}
for (t in c("regime_metrics", "cost_sensitivity", "model_runtime", "dataset_summary"))
  if (file.exists(tb(paste0(t, ".csv")))) md_table(read.csv(tb(paste0(t, ".csv"))), paste0(t, ".md"))
