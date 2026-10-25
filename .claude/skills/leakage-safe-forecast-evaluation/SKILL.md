---
name: leakage-safe-forecast-evaluation
description: Design and run leakage-controlled, pre-registered financial forecasting experiments in R - point-in-time features, embargoed monthly walk-forward, HAR/GHAR baselines, naive baselines, Diebold-Mariano tests with Holm/BH correction, stationary bootstrap CIs, Model Confidence Set, power analysis and exact linear SHAP. Use when adding a model, feature set, target or hypothesis test, or when checking a result for look-ahead bias or p-hacking.
---

# Leakage-safe forecast evaluation

Q-Stock code: `R/walk_forward.R`, `R/evaluation.R`, `R/features.R`, `scripts/05*`, `11`, `14`–`23`.

## Protocol (do not weaken)

1. **Point-in-time features.** A feature dated t uses data up to the close of t only (trailing windows, `sides = 1` filters). Graph correlations use the trailing 60 days ending at t.
2. **Labels:** direction = t+1; volatility T1 = `log Σ_{k=1..5} r²_{t+k}`. Store `label_date` = last date the label reveals.
3. **Walk-forward:** 24-month rolling train window, one test month per fold. `wf_split()` keeps train rows with `date < M` **and** `label_date < M` (embargo).
4. **Scaling/tuning on train only.** Nested tuning picks hyper-parameters on the last 6 months of each training window; the test month is never used for any choice.
5. **Baselines first:** naive base rate (direction), HAR-RV, and the stronger linear graph-HAR (GHAR). A new model must beat GHAR to claim value.
6. **Matched controls:** classical diffusions on the same graph and a random-graph control, so a gain can be attributed to the walk rather than to pooling.

## Leakage tests to write

- Perturb rows after t; assert features at ≤ t are unchanged.
- Assert no training `label_date` falls inside the test month.
- Sanity: AUC near 0.5 on direction is expected; a 70%+ daily direction accuracy signals leakage.

## Inference recipe

| Question | Tool (`R/evaluation.R`) |
|---|---|
| Is model A better than B? | `dm_test()` on daily loss differences, Newey–West variance |
| Several pre-registered contrasts | `holm_adjust()` within the family (e.g. 6 ω-vs-1 tests) |
| Ablation families | `bh_adjust()` |
| CI for a mean loss difference | `stationary_boot_ci()` (mean block 20, 1000 reps) |
| Joint comparison | Model Confidence Set, Tmax, B = 2000 (`scripts/17_ghar_mcs.R`) |
| Volatility loss | MSE of log RV (primary) and `qlike()` (secondary) |
| Cross-sectional skill | `rank_ic()` with Newey–West t |
| Could the test detect a signal? | Power analysis: inject a feature with known correlation, 5 seeds per strength (`scripts/19_power_analysis.R`) |
| Which features are used? | Exact linear SHAP φⱼ = βⱼ(xⱼ − E_train[xⱼ]); usage, not accuracy |

## Pre-registration discipline

- Write hypotheses, grid, targets, losses and corrections in `docs/research/` **before** running.
- Report every pre-specified cell whatever the outcome; label everything else *exploratory*.
- Never add ω values, drop markets or switch losses after seeing results.
- Economic value: translate forecast gains into a simple portfolio (inverse-volatility, 10 bps costs) and test the realised-risk difference by bootstrap; a significant forecast gain may have no economic value.
- A well-powered null is a result. State it plainly.
