# Pre-registration: Q-Stock v2 hypotheses

Written on **2026-10-22, before any v2 experiment was run**. The v1 results (`docs/results/results.md`) are already known and motivate v2.
Analyses not listed here will be labelled *exploratory* in any write-up.

## Motivation from v1

* For next-day direction, no feature set (classical, classical-diffusion or quantum-walk) beat a naive base-rate predictor on log-loss, in either market.
* Quantum-walk features were compared with *different* classical features. That design cannot isolate the effect of quantum coherence.

## Core design change: one walk family with a quantumness dial

A **quantum stochastic walk (QSW)** (Lindblad master equation) on the same market graph:

dρ/dt = −(1−ω)·i[H, ρ] + ω·Σ_{i≠j} γ_ij ( L_ij ρ L_ij† − ½{L_ij† L_ij, ρ} ),

with H = L (the weighted graph Laplacian), L_ij = |i⟩⟨j| and γ_ij = W_ij.

* ω = 0 gives the closed CTQW used in v1 (verified by unit test).
* ω = 1 gives the classical continuous-time random walk exp(−tL), the v1 heat kernel (verified by unit test).
* 0 < ω < 1 gives partially coherent dynamics.

Node features are computed from the QSW distribution exactly as in v1: `self`, `mom` and `ent`, plus `volspill`, the walk-weighted neighbour volatility.
**Pre-specified grid: ω ∈ {0, 0.1, 0.25, 0.5, 0.75, 0.9, 1}.** No other ω values will be reported as confirmatory.

## Targets

* **T1 (primary):** log of next-5-day realised variance per stock, log Σ_{k=1..5} r²_{t+k}. Baseline: HAR-RV regression (log RV over 1, 5 and 22 days). Model: OLS, walk-forward as in v1, with the embargo extended to 5 trading days.
  Loss: MSE of log RV. Secondary loss: QLIKE.
* **T2 (secondary):** next-day direction (v1 target), logistic regression, log-loss. Kept for continuity.
* **T3 (secondary):** cross-sectional rank IC (Spearman) of the predicted next-day return against the realised return.

## Hypotheses

* **H1:** Adding walk-diffused volatility features from the market graph improves T1 over HAR-RV (mean loss difference < 0, DM test).
  This tests the *graph*, not quantumness.
* **H2 (quantum hypothesis):** For T1, out-of-sample loss is **not** minimised at ω = 1, i.e. some ω < 1 beats the classical limit.
  Test: DM test of the best pre-specified ω < 1 against ω = 1, with a **Holm correction over the 6 comparisons**.
* **H3:** The random-graph control does not reproduce any H1 gain.
* **H4:** Regime-adaptive fusion (v1 hypothesis) is not re-tested as confirmatory; v1 rejected it.

## Decision rules

* Significance: two-sided α = 0.05 after Holm (H2) or Benjamini–Hochberg (families of ablations).
* Every pre-specified ω, target and market is reported, whatever the outcome.
* If H2 is not supported, the paper reports that the coherent part of the walk adds nothing beyond its classical limit on this data.

## Fixed settings (unchanged from v1 unless stated)

corr_window 60, kNN k = 4, τ grid (0, 2] with 10 points, train window 24 months, monthly folds, 2015-01 to 2026-09, 20 NSE + 20 NASDAQ large caps.
