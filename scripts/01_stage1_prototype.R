# Stage 1 prototype: DTQW / CTQW demos + classical logistic baseline on
# synthetic data. Run from the project root:  Rscript scripts/01_stage1_prototype.R
#
# Synthetic data is for software validation only. Results here say nothing
# about real market predictability.

for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
dir.create("results", showWarnings = FALSE)
dir.create("data/synthetic", recursive = TRUE, showWarnings = FALSE)

cat("== DTQW: Hadamard walk on a 101-cycle, 40 steps ==\n")
n <- 101
states <- dtqw_evolve(dtqw_cycle_operator(n), dtqw_cycle_initial_state(n, 51), 40)
p_dtqw <- dtqw_cycle_position_probs(states[41, ], n)
cat(sprintf("norm = %.12f, std(position) = %.2f (classical RW ~ %.2f)\n",
            sum(p_dtqw), sqrt(sum(p_dtqw * (seq_len(n) - 51)^2) - sum(p_dtqw * (seq_len(n) - 51))^2),
            sqrt(40)))

cat("\n== CTQW: Laplacian walk on a 10-cycle, t = 0..5 ==\n")
adj <- matrix(0, 10, 10)
for (i in 1:10) adj[i, (i %% 10) + 1] <- adj[(i %% 10) + 1, i] <- 1
H <- ctqw_hamiltonian(adj)
ct <- ctqw_evolve(H, ctqw_initial_state(10, 1), times = 0:5)
print(round(Mod(ct)^2, 3))

cat("\n== Classical logistic baseline (synthetic GARCH data, single chrono split) ==\n")
prices <- simulate_garch_prices(n_days = 750)
write.csv(prices, "data/synthetic/garch_prices.csv", row.names = FALSE)
feats <- build_features(prices)
res <- fit_logit_baseline(feats)
cat("train/test cutoff:", format(res$cutoff), "\n")
metrics <- rbind(train = res$train_metrics, test = res$test_metrics)
print(round(metrics, 4))
write.csv(data.frame(split = rownames(metrics), metrics),
          "results/stage1_baseline_metrics.csv", row.names = FALSE)
cat("\nExpected on this data: test accuracy near 0.5 (no predictable signal).\n")
writeLines(capture.output(sessionInfo()), "results/stage1_sessionInfo.txt")
