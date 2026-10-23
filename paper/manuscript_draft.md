# Does quantum coherence help forecast volatility? A pre-registered quantum-to-classical audit of quantum stochastic walks on NSE and NASDAQ correlation networks

> **Framing update (after the GHAR check, `docs/results_v2.md`).** The pre-registered within-family effect (intermediate ω beats ω = 1 on NASDAQ) holds.
> However, QSW features give **no gain over a simple linear graph-HAR (GHAR) baseline** in either market.
> The paper should therefore be framed as a rigorous audit: coherence measurably changes the diffusion, but it adds no forecasting value beyond classical graph spillovers.
> The abstract below must be rewritten accordingly before submission.

*Draft v0.1, 2026-10-22. All numbers come from `results/tables`; regenerate before submission. Items marked **[VERIFY]** must be checked against the primary source.*

## Abstract (draft)

Quantum walks have been proposed as models of financial dynamics, but evidence that they add forecasting value beyond their classical counterparts is scarce.
We build daily k-nearest-neighbour correlation graphs for 20 NSE and 20 NASDAQ large-cap stocks (2015–2026). On each graph we simulate a quantum stochastic walk (QSW) whose decoherence parameter ω interpolates between a closed continuous-time quantum walk (ω = 0) and the classical continuous-time random walk (ω = 1).
Walk-derived volatility-spillover features are added to a HAR-RV model of 5-day realised variance and evaluated in a monthly walk-forward design with label embargo, under hypotheses pre-registered before any run.
On NASDAQ, intermediate decoherence (ω = 0.25) lowers out-of-sample MSE relative to the classical limit (Δ = −0.0037, 95% bootstrap CI [−0.0052, −0.0019], Holm-adjusted p = 4.8×10⁻⁶; the most significant contrast is ω = 0.5, Δ = −0.0025, Holm-adjusted p = 4.7×10⁻⁸). The improvement holds under QLIKE, in both 2017–2021 and 2022–2026, and for 17 of 20 stocks. The fully coherent walk gives no improvement.
On NSE the classical limit is best, and a random-graph control reproduces the gain over HAR-RV.
For next-day direction, no feature set beats a naive base-rate predictor. In an inverse-volatility portfolio, the statistical gain yields no material economic benefit: Sharpe ratios are unchanged, and the realised-risk differences are either not significant (NASDAQ) or negligible in size (NSE).
We conclude that partial coherence can help, depending on the market, while a general quantum advantage is not supported. All walks are classically simulated, and the full Hadoop/Hive/Spark pipeline is released.

## 1 Introduction
- Motivation: network spillovers in volatility; quantum walks as alternative diffusion kernels (interference, localisation).
- Gap (from `docs/novelty_audit.md` and the 45-paper survey):
  - Prior quantum-walk finance work models return distributions (De Backer et al. [VERIFY]), portfolio weights (Chang et al., 2026, npj Unconventional Computing) or network entropy (Bai et al., IJCAI 2020). It does not isolate whether coherence helps forecasting.
  - Recent ML stock-prediction papers rarely use walk-forward evaluation, naive baselines, costs or multiple-testing control.
- Contributions:
  1. A quantumness-dial design (QSW ω-sweep) that separates coherence from graph structure.
  2. A pre-registered, leakage-controlled protocol with Holm/BH correction, bootstrap CIs and a random-graph control.
  3. Evidence on two markets: a NASDAQ-specific benefit of intermediate coherence, and negative results elsewhere.
  4. A reproducible Big Data pipeline (HDFS, MapReduce, Hive, sparklyr) and a CPU/GPU scalability analysis.

## 2 Related work
- Quantum walks: DTQW (Aharonov et al. 1993 [VERIFY]), CTQW (Farhi & Gutmann 1998 [VERIFY]), QSW (Whitfield, Rodríguez-Rosario & Aspuru-Guzik 2010 [VERIFY]).
- Quantum walks in finance: P1–P6 in `docs/novelty_audit.md`.
- Volatility forecasting: HAR-RV (Corsi 2009 [VERIFY]); network spillovers (Diebold & Yilmaz [VERIFY]).
- Forecast evaluation: Diebold–Mariano (1995 [VERIFY]); stationary bootstrap (Politis & Romano 1994 [VERIFY]); Holm (1979 [VERIFY]).

## 3 Data and leakage control
- Yahoo daily OHLCV, 2015-01-01 to 2026-10-21. Cleaning rules: holiday bars, NA-safe windows (`results/data_quality_report.txt`).
- Point-in-time rules:
  - features use data up to the close of t only
  - labels are t+1 (direction) or t+1..t+5 (RV)
  - training rows whose label is revealed inside the test month are dropped
- Unit tests that perturb future data and assert features are unchanged (`tests/`).

## 4 Methods
- 4.1 Market-state graph: 60-day correlations, symmetrised kNN (k = 4), weights max(ρ, 0.01).
- 4.2 QSW: Lindblad equation (`docs/preregistration_v2.md`). Limits ω = 0 (CTQW) and ω = 1 (classical CTRW) are verified to 10⁻⁶ by unit tests. RK4 integration with h = 0.02, time-averaged over τ ∈ {0.2, …, 2}.
- 4.3 Node features: self, mom, ent, volspill.
- 4.4 Models: HAR-RV OLS (T1), logistic regression (T2), rank IC (T3). Exploratory baselines: graph-HAR (GHAR), elastic net, LightGBM and a QLIKE-trained MLP (GPU), all with nested walk-forward validation.
- 4.5 Evaluation: monthly walk-forward; DM with Newey–West variance; stationary bootstrap (mean block 20, 1000 reps); Holm within each pre-registered family.

## 5 Results
- Table 1: T1 MSE / QLIKE / OOS R² by ω (`v2_T1_volatility.md`).
- Figure 1: the quantumness dial (`fig7_quantumness_dial.png`).
- Table 2: H1–H3 tests (`v2_hypothesis_tests.md`).
- Table 3: robustness by sub-period and ticker (`v2_robustness_*.csv`; exploratory).
- Table 4: direction results and the naive baseline (`experiment_results.md`, `naive_baseline.csv`).
- Figure 2: SHAP attributions by regime (`fig9_explainability_shap.png`).
- Table 5 (exploratory): strongest classical baselines vs QSW, with nested validation (`v3_tuned_models.csv`, `v3_lightgbm.csv`, `v3_mlp_vs_linear.csv`).
  - Linear GHAR is best on NASDAQ (OOS R² 0.348); a simple combination is best on NSE (0.178).
  - Adaptive-ω QSW, elastic net and LightGBM never beat it significantly.
  - A QLIKE-trained GPU MLP is no better on NASDAQ (QLIKE p = 0.78) and significantly worse on NSE (Holm p = 0.001). Its MSE is far worse because of a systematic upward bias (about +0.8 log points). One fixed architecture was trained, without a hyper-parameter search.
  - Adding QSW features never improves any model class.

## 6 Big Data system and scalability
- Architecture: HDFS (WebHDFS), Java MapReduce with combiner (5,680 ticker-month groups; matches R to 1.8×10⁻¹⁵), Hive tables and window queries, sparklyr on Spark 3.5 (7.49 M rows in 4.8 s).
- Simulation cost vs N (`qw_scalability.csv`); GPU vs CPU (`gpu_benchmark.csv`, fig8).

## 7 Discussion and limitations
Survivorship bias, unofficial data, a single pre-registered graph construction, small effect sizes, economic evaluation limited to a simple inverse-volatility portfolio, sentiment not evaluated (the GDELT download stopped at 21/40 tickers under HTTP 429 rate-limiting; partial data were not used), and classical simulation only.

## 8 Reproducibility
`docs/runbook.md`; all scripts, unit tests, the pre-registration and the logs are in the repository.
