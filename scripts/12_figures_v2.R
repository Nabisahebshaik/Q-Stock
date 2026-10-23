# v2 figures: the "quantumness dial". Loss difference vs omega
# (omega = 0 closed CTQW ... omega = 1 classical walk), with 95% stationary-bootstrap CIs.

suppressPackageStartupMessages(library(ggplot2))
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
ensure_dirs()
PAL <- c("#2a78d6", "#eb6834", "#1baf7a", "#eda100")
theme_qs <- theme_minimal(base_size = 11) +
  theme(plot.background = element_rect(fill = "#fcfcfb", colour = NA),
        text = element_text(colour = "#0b0b0b"), axis.text = element_text(colour = "#52514e"),
        panel.grid.minor = element_blank(), panel.grid.major = element_line(colour = "#e6e5e1", linewidth = 0.3),
        legend.position = "top", plot.title.position = "plot",
        plot.caption = element_text(colour = "#52514e", hjust = 0))

TT <- read.csv(file.path(QS$paths$tables, "v2_hypothesis_tests.csv"))
omega_of <- function(x) as.numeric(sub(".*_w", "", x)) / 100

h1 <- TT[(TT$hypothesis == "H1" & TT$loss == "mse") | TT$hypothesis == "T2_vs_classical", ]
h1$omega <- omega_of(h1$model_a)
h1$panel <- ifelse(h1$target == "T1", "T1: 5-day log realised variance (MSE vs HAR-RV)",
                   "T2: next-day direction (log-loss vs classical)")
rnd <- TT[TT$hypothesis == "H3" & TT$loss == "mse", ]; rnd$omega <- omega_of(rnd$model_a)
rnd$panel <- "T1: 5-day log realised variance (MSE vs HAR-RV)"

p <- ggplot(h1, aes(omega, mean_diff_a_minus_b, colour = market, shape = market)) +
  geom_hline(yintercept = 0, colour = "#8a8984", linetype = 2, linewidth = 0.4) +
  geom_ribbon(aes(ymin = ci_lo, ymax = ci_hi, fill = market), alpha = 0.12, colour = NA) +
  geom_line(linewidth = 0.6) + geom_point(size = 2.3) +
  geom_point(data = rnd, shape = 4, size = 3, stroke = 1) +
  facet_wrap(~panel, scales = "free_y", ncol = 1) +
  scale_colour_manual(values = PAL[1:2], name = NULL) + scale_fill_manual(values = PAL[1:2], name = NULL) +
  scale_shape_manual(values = c(16, 17), name = NULL) +
  scale_x_continuous(breaks = c(0, 0.1, 0.25, 0.5, 0.75, 0.9, 1),
                     labels = c("0\nCTQW", "0.1", "0.25", "0.5", "0.75", "0.9", "1\nclassical")) +
  labs(x = expression(omega~"(decoherence: 0 = fully quantum, 1 = classical walk)"),
       y = "Mean daily loss difference (below 0 = better than baseline)",
       title = "Quantum stochastic walk features across the quantum-to-classical dial",
       caption = "Shaded: 95% stationary-bootstrap CI. Crosses: random-graph controls. Walk-forward 2017-2026, 20 stocks per market.") +
  theme_qs
ggsave(file.path(QS$paths$figures, "fig7_quantumness_dial.png"), p, width = 9, height = 7, dpi = 300, bg = "#fcfcfb")
message("wrote fig7_quantumness_dial.png")

# Markdown tables
md <- function(df, file) {
  df[] <- lapply(df, function(x) if (is.numeric(x)) signif(x, 4) else x)
  writeLines(c(paste("|", paste(names(df), collapse = " | "), "|"), paste("|", paste(rep("---", ncol(df)), collapse = " | "), "|"),
               apply(df, 1, function(r) paste("|", paste(r, collapse = " | "), "|"))), file.path(QS$paths$tables, file))
}
md(read.csv(file.path(QS$paths$tables, "v2_T1_volatility.csv")), "v2_T1_volatility.md")
md(read.csv(file.path(QS$paths$tables, "v2_T2_direction.csv")), "v2_T2_direction.md")
md(TT[, c("hypothesis", "target", "loss", "market", "model_a", "model_b", "mean_diff_a_minus_b", "ci_lo", "ci_hi",
          "dm_stat", "p_value", "p_holm")], "v2_hypothesis_tests.md")
