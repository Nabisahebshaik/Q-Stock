# Q-Stock v2 results: quantum stochastic walk "quantumness dial"

Data: Yahoo daily OHLCV, 2015-01-01 to 2026-10-21, 20 NSE + 20 NASDAQ current large caps (survivorship bias: see limitations).
Evaluation: monthly walk-forward, 24-month rolling training window, embargo on label dates, test months 2017-03 to 2026-10.
Pre-registration: `docs/preregistration_v2.md`, written before any v2 run.
Tables: `results/tables/v2_*.csv`. Figure: `results/figures/fig7_quantumness_dial.png`.

All walks are **classical simulations** of quantum dynamics (RK4 integration of the Lindblad equation in R). No quantum hardware was used and no quantum speed-up is claimed.

## T1 (primary): 5-day-ahead log realised variance, OLS

| Market | HAR-RV MSE | best QSW MSE (ω) | QSW ω = 1 (classical) MSE | OOS R², HAR → best QSW |
|---|---|---|---|---|
| NSE | 0.9708 | 0.9436 (ω = 1) | 0.9436 | 0.153 → 0.176 |
| NASDAQ | 1.0565 | 1.0382 (ω = 0.25) | 1.0419 | 0.342 → 0.347 |

### Pre-registered hypotheses (Holm-corrected within each family of tests)

| Hypothesis | NSE | NASDAQ |
|---|---|---|
| **H1** graph features beat HAR-RV | MSE: **supported** for all ω (p_Holm = 0.0012). QLIKE: not significant after Holm (p_Holm = 0.145) | MSE: **supported only at ω = 0.25** (p_Holm = 0.040); others p_Holm 0.06–0.08. QLIKE: not significant |
| **H2** some ω < 1 beats the classical limit ω = 1 | **Not supported.** The classical limit is best; ω ≤ 0.25 is *significantly worse* on MSE (p_Holm ≤ 0.027), and no ω is significant on QLIKE | **Supported.** MSE: ω = 0.1–0.9 better than ω = 1 (largest gain at ω = 0.25: Δ = −0.0037, 95% CI [−0.0052, −0.0019], p_Holm = 4.8×10⁻⁶; most significant at ω = 0.5: Δ = −0.0025, p_Holm = 4.7×10⁻⁸). QLIKE: ω = 0.25–0.9 better (p_Holm 0.02 to 7×10⁻⁵). The pure CTQW (ω = 0) is **not** better |
| **H3** random-graph control does not reproduce the H1 gain | **Not supported**: random graphs give a similar, significant gain (Δ ≈ −0.020, p_Holm = 7×10⁻⁴), so the NSE gain is mostly pooled market-wide volatility, not correlation structure | **Supported**: random-graph gain not significant (p = 0.29) |

### Exploratory robustness (not pre-registered; `scripts/14_v2_robustness.R`)

* **NASDAQ H2 is stable over time.** ω = 0.25–0.9 vs ω = 1 is significant in both 2017–2021 and 2022–2026 (all p < 0.001) with similar effect sizes.
* **NASDAQ H2 is consistent across stocks.** 85–95% of the 20 stocks individually have lower loss at ω = 0.25–0.9 than at ω = 1 (sign test p ≤ 0.003).
* **NSE.** ω < 1 is worse, mainly in 2022–2026; 75–100% of stocks are worse at ω ≤ 0.75.

### Interpretation (to be stated with this level of caution)

On NASDAQ large caps, *partially decoherent* quantum stochastic walks (ω ≈ 0.25–0.5) on the daily correlation graph produce volatility-spillover features that forecast 5-day realised variance slightly but consistently better than their classical-diffusion limit. The pure coherent walk (ω = 0) does not.
The effect is small (about 0.36% lower MSE) and does **not** replicate on NSE, where the classical limit is best.
What the data support is a **market-dependent** benefit of intermediate coherence. They do **not** support a general quantum advantage.

## T2 / T3: next-day direction (secondary)

* Log-loss: no QSW variant improves on classical features in either market (no Holm-significant gain). The NASDAQ point estimates are slightly worse.
* AUC stays at 0.503–0.512, as in v1.
* Rank IC (exploratory; no baseline comparison was pre-registered): NASDAQ QSW ω = 0–0.1 has mean daily IC 0.0156–0.0158 (Newey–West t ≈ 2.7–2.8) vs 0.0102 (t = 1.75) for classical features. NSE ICs are 0.006–0.009 (t < 1.8).

## Stronger classical baseline: GHAR and Model Confidence Set (exploratory; `scripts/17_ghar_mcs.R`)

Added after the literature check found that graph-augmented HAR is established (GNNHAR: Zhang, Pu, Cucuringu & Dong, IJF 41(1), 2025, doi:10.1016/j.ijforecast.2024.09.002).
GHAR here means HAR plus the correlation-weighted one-hop neighbour averages of the HAR terms, on the **same** daily kNN graph.
All models are evaluated on a common sample.

| Comparison | NSE MSE / QLIKE p | NASDAQ MSE / QLIKE p | Reading |
|---|---|---|---|
| GHAR vs HAR | 3.1e-5 / 0.029 (GHAR better) | 5.5e-4 / 0.010 (GHAR better) | A simple classical graph model clearly helps |
| HAR+QSW(0.25) vs GHAR | 0.80 / 0.24 | 0.39 / 0.064 | QSW features are **no better than GHAR** |
| GHAR+QSW(0.25) vs GHAR | 0.19 / 0.16 | 0.41 / **0.0038 (worse)** | QSW adds **nothing** beyond GHAR (worse on NASDAQ QLIKE) |
| GHAR+QSW(0.25) vs GHAR+QSW(1) | 0.14 / 0.87 | **0.011 (better)** / 0.17 | The ω effect on NASDAQ survives on MSE only |
| 90% MCS (Tmax, B = 2000) | all 6 models retained | all 6 models retained | Daily losses cannot discriminate the models |

**Revised overall conclusion.**
The pre-registered H2 result stands: within the QSW family, intermediate decoherence beats the classical limit on NASDAQ.
But QSW features provide **no forecasting gain over a simple linear graph-HAR baseline** in either market.
Quantum coherence changes the walk's diffusion pattern measurably; it does not yield a practically better volatility forecast.
This matches recent leakage-controlled audits of quantum ML in finance (Shen 2026, arXiv:2607.20168: "no quantum advantage of any kind").

## Power analysis / positive control (`scripts/19_power_analysis.R`)

A synthetic feature with known correlation to the next-day return is injected; walk-forward logistic regression with DM test vs classical; 5 noise seeds per strength.

| Signal corr. with next-day return (NASDAQ / NSE) | Detection rate NASDAQ | Detection rate NSE |
|---|---|---|
| ≈0 (pure noise) | 0% | 0% |
| 0.015 / 0.008 | 0% | 0% |
| 0.025 / 0.018 | 20% | 0% |
| 0.035 / 0.028 | 80% | 20% |
| 0.055 / 0.048 | 100% | 80% |
| ≈0.10 | 100% | 100% |

There are no false positives. The protocol reliably (≥ 80%) detects features with return correlation of about **0.035 (NASDAQ) to 0.05 (NSE)**.
The direction-prediction nulls therefore bound the incremental information in the walk features to below that level. The tests had power; the null is informative.

## Explainability (exact linear SHAP; `scripts/15_explainability.R`)

For linear and logistic models with standardised features, φⱼ = βⱼ(xⱼ − E_train[xⱼ]) exactly.
The table gives each group's share of mean |SHAP| at QSW ω = 0.25.

| Task | Market | QSW share, low-vol regime | QSW share, high-vol regime |
|---|---|---|---|
| T1 volatility | NASDAQ | 0.327 | 0.341 |
| T1 volatility | NSE | 0.567 | 0.575 |
| T2 direction | NASDAQ | 0.288 | 0.277 |
| T2 direction | NSE | 0.526 | 0.522 |

Caveats:
- SHAP measures how much a model *uses* a feature, not whether the feature improves out-of-sample loss; for that, see the H1–H3 tests.
- `q_volspill` is correlated with the HAR terms, so the split between correlated features is partly arbitrary.
- The large NSE share fits H3: the NSE gain mostly comes from pooled market-wide volatility, which random graphs also provide.

Figure: `results/figures/fig9_explainability_shap.png`.

## Economic value (exploratory; `scripts/16_economic_value.R`)

Long-only inverse-volatility portfolios, rebalanced daily, 10 bps one-way costs, using each model's T1 forecast:

| Market | HAR | QSW ω = 0.25 | QSW ω = 1 | Equal weight |
|---|---|---|---|---|
| NSE Sharpe | 1.050 | 1.015 | 1.016 | 1.066 |
| NASDAQ Sharpe | 1.032 | 1.023 | 1.023 | 1.113 |

The statistically significant NASDAQ forecast gain **does not translate into economic value** in this simple use:
- Portfolio volatility and Sharpe are essentially unchanged.
- The realised-risk difference between ω = 0.25 and ω = 1 (paired daily squared portfolio returns, stationary bootstrap) is not significant on NASDAQ (95% CI includes 0).
- On NSE, ω = 0.25 gives slightly lower realised risk than ω = 1 (95% CI [−3.3×10⁻⁷, −8.4×10⁻⁸], excluding 0). The size is negligible: annualised volatility 15.747% vs 15.762%, and Sharpe 1.015 vs 1.016. This is opposite in sign to the NSE forecast-accuracy result, where ω = 1 is better.
- Equal weight has the highest Sharpe, which is partly a survivorship-bias effect.

## Limitations

1. Survivorship bias: the universe is today's large caps.
2. Yahoo is an unofficial source with back-adjusted prices.
3. One graph construction (60-day correlation, k = 4) was pre-registered. Sensitivity to these choices is exploratory work.
4. Effect sizes are small. Economic value was evaluated only with a simple inverse-volatility portfolio; volatility-targeting and risk-budgeting uses are not evaluated.
5. Sentiment (RQ5) was not evaluated: the GDELT download stopped at 21/40 tickers because of HTTP 429 rate-limiting (deadline 2026-10-23 12:06). Partial data were not used.
