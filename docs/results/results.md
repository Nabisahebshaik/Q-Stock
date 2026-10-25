# Q-Stock: consolidated results

Data: Yahoo daily OHLCV for 20 NSE and 20 NASDAQ current large caps, 2015-01-01 to 2026-10-21.
Walk-forward evaluation: 24-month rolling training window, monthly test folds from 2017-03, label embargo.
Every number comes from `results/tables/*.csv`, produced by the scripts named in each section.
All quantum walks are **classical simulations**.

## 1. Data and engineering validation

| Check | Result | Source |
|---|---|---|
| Cleaning | Holiday bars dropped (NSE 2025-03-18, 2026-01-15); NA-safe rolling windows; 2 genuine extreme moves kept (AMD 2016-04-22, NFLX 2022-04-20) | `results/data_quality_report.txt` |
| Unit tests | 32 test blocks, 145 expectations, all pass. They cover unitarity, Hermiticity, the QSW limits, feature-leakage perturbation tests and the embargo | `tests/` |
| Hadoop MapReduce (Java, combiner, YARN) | 5,680 ticker-month groups (data to 2026-10-21, reloaded 2026-10-23); matches an independent R computation exactly (count difference 0, max error 1.8×10⁻¹⁵) | `results/stage3_hadoop_hive_log.txt` |
| Hive | External tables, window-function queries; the MR-vs-raw consistency query returns 0 mismatches (re-checked 2026-10-23) | `results/tables/hive_*.tsv` |
| Spark 3.5 (sparklyr) | Rolling features and point-in-time sentiment join; agree with R to 10⁻¹⁵ (features) and 6.5×10⁻⁷ (sentiment decay); 7.49 M rows in 4.8 s (re-run 2026-10-23 on data to 2026-10-21) | `results/tables/spark_scaling.csv` |
| Power analysis | 0% false positives; ≥ 80% detection at return correlation ≈ 0.035 (NASDAQ) / 0.05 (NSE) | `power_analysis_summary.csv` |

## 2. Next-day direction (v1; `05_experiments.R`, `05b_naive_baseline.R`)

| | NSE | NASDAQ |
|---|---|---|
| Naive base-rate log-loss | **0.6930** | **0.6921** |
| Best model log-loss (logit, classical) | 0.6937 | 0.6930 |
| AUC range, all 16 model × feature-set runs | 0.5025–0.5070 | 0.5012–0.5123 |
| Always-long Sharpe (net) | **1.02** | **1.06** |
| Best model-strategy Sharpe (net, 10 bps) | 0.49 | 0.99 |

* No model or feature set beats the naive predictor, and no strategy beats always-long.
* Logistic regression: walk features never significantly improve log-loss. The regime-adaptive variant is significantly worse (DM p = 1.6×10⁻⁵ NASDAQ, 5.9×10⁻⁴ NSE).
* Random forest: walk features improve RF's own log-loss (e.g. NASDAQ fusion p = 4.2×10⁻¹⁰), but RF stays worse than plain logistic regression. These gains repair calibration; they do not reveal predictability.
* Ablations (`ablation_results.csv`) and the random-graph control: every significant DM statistic for logistic regression is positive, meaning walk features add loss.

## 3. Volatility and the quantum-to-classical dial (v2; pre-registered)

See `docs/results/results_v2.md` for the full tables. In summary:

* **H2 (quantum hypothesis), NASDAQ: supported.** QSW at ω = 0.25 beats the classical limit ω = 1.
  - MSE: Δ = −0.0037, 95% CI [−0.0052, −0.0019], Holm p = 4.8×10⁻⁶. The most significant contrast is ω = 0.5 (Δ = −0.0025, Holm p = 4.7×10⁻⁸).
  - It also holds under QLIKE, in 2017–2021 and in 2022–2026, and for 17/20 stocks.
  - The fully coherent walk (ω = 0) does not help.
* **H2, NSE: not supported.** The classical limit is best.
* **H1:** graph features beat HAR-RV on MSE on NSE for every ω (Holm p = 0.0012), but on NASDAQ only at ω = 0.25 (Holm p = 0.040; other ω 0.06–0.08). Under QLIKE, nothing is significant after Holm.
* **H3:** on NSE the random-graph control reproduces the gain (market-wide volatility pooling); on NASDAQ it does not.
* **GHAR audit (exploratory):**
  - a simple linear graph-HAR beats HAR (p ≤ 5.5×10⁻⁴);
  - QSW features do **not** beat GHAR, and add nothing on top of it (worse under QLIKE on NASDAQ, p = 0.004);
  - the 90% Model Confidence Set retains all models.
* **Economic value:** no material gain in inverse-volatility portfolios (Sharpe changes ≤ 0.001 between ω = 0.25 and ω = 1). NASDAQ realised-risk difference: not significant. NSE: ω = 0.25 has statistically lower realised risk, but by a negligible 0.015 percentage points of annualised volatility.
* **Explainability (exact linear SHAP):** QSW features carry 33% (NASDAQ) and 57% (NSE) of the attribution mass for volatility. This is usage, not added accuracy.

## 3b. Best achievable forecasts: nested-validation tuning (`20_tuned_models.R`, `21_lightgbm_nested.R`)

All hyper-parameters are chosen on the **last 6 months of each training window**, with the embargo respected. The test month is never used for any choice.

| Market | Model | MSE | QLIKE | OOS R² | vs GHAR (DM p, Holm) |
|---|---|---|---|---|---|
| NSE | HAR | 0.9695 | 0.6489 | 0.154 | — |
| NSE | GHAR | 0.9455 | 0.6234 | 0.175 | — |
| NSE | GHAR + QSW (ω chosen monthly) | 0.9437 | 0.6226 | 0.176 | n.s. (0.73) |
| NSE | Elastic net, all 27 features | 0.9495 | 0.6292 | 0.171 | n.s. |
| NSE | **Combination (mean of the three)** | **0.9422** | **0.6215** | **0.178** | −0.0033, p = 0.058 (Holm 0.17), n.s. |
| NASDAQ | HAR | 1.0524 | 0.7971 | 0.338 | — |
| NASDAQ | **GHAR** | **1.0363** | **0.7771** | **0.348** | — |
| NASDAQ | GHAR + QSW (ω chosen monthly) | 1.0404 | 0.7900 | 0.346 | **worse** (QLIKE Holm 1.9e-4) |
| NASDAQ | Elastic net, all 27 features | 1.0460 | 0.7911 | 0.342 | **worse** (MSE Holm 0.007) |
| NASDAQ | Combination | 1.0379 | 0.7833 | 0.347 | n.s. (MSE); worse (QLIKE Holm 0.005) |

* The best forecasts are **GHAR on NASDAQ** and the **combination on NSE**. Both clearly beat HAR-RV on MSE (NSE combination: Holm p = 1.5×10⁻⁶; NASDAQ GHAR: p = 5.5×10⁻⁴), but neither gain is attributable to the quantum features.
* Choosing ω from validation data is unstable (NASDAQ: ω = 0 chosen in 38/115 months, although 0.25 is best over the full grid). Monthly selection chases noise.
* **LightGBM** (nonlinear; nested grid over leaves × min-data, early stopping on inner validation) is **significantly worse than linear GHAR**:
  - NASDAQ OOS R² 0.329 vs 0.348 (MSE p = 8.6e-9)
  - NSE OOS R² 0.144 vs 0.175 (p = 2.2e-3)
  - Adding QSW features inside LightGBM changes nothing (MSE p = 0.69 NASDAQ, 0.43 NSE) and is worse under QLIKE on NASDAQ (p = 0.016).
* **GPU MLP trained with QLIKE** (`18_mlp_qlike_gpu.R`, compared in `23_mlp_vs_linear.R`):
  - Setup: 2×32 ReLU network, 3-seed ensemble, Adam, early stopping on the last 10% of each training window, trained on the RTX 4060 (164 min).
  - The comparison uses identical rows to the linear models: 48,400 NASDAQ and 47,500 NSE forecasts, same folds.

  | Market | Model | QLIKE | MSE | OOS R² | Mean bias (log) |
  |---|---|---|---|---|---|
  | NASDAQ | Linear GHAR | **0.7771** | **1.0363** | **0.348** | −0.03 |
  | NASDAQ | MLP, GHAR inputs | 0.7885 | 2.6325 | −0.655 | +0.80 |
  | NASDAQ | MLP, GHAR + QSW ω = 0.25 | 0.9555 | 3.6722 | −1.309 | +0.99 |
  | NSE | Linear GHAR | 0.6234 | 0.9455 | 0.175 | +0.00 |
  | NSE | MLP, GHAR inputs | 0.7929 | 3.1687 | −1.766 | +0.82 |
  | NSE | MLP, GHAR + QSW ω = 0.25 | 0.7988 | 3.0832 | −1.691 | +0.81 |

  - **QLIKE** (the MLP's own training loss, so the fair comparison):
    - NASDAQ: the MLP with GHAR inputs is statistically indistinguishable from linear GHAR (Δ = +0.012, 95% CI [−0.12, 0.18], p = 0.78).
    - NSE: it is significantly worse (Δ = +0.170, Holm p = 0.001).
  - **MSE:** the MLP is far worse in both markets (Holm p ≤ 1.1×10⁻⁹). Most of the gap is a systematic upward bias of about 0.8 log points. QLIKE's optimum is log E[RV] rather than E[log RV], so some upward bias on the log scale is expected; the observed bias is larger than that alone would explain.
  - **QSW inside the MLP:**
    - Adding ω = 0.25 features is worse on NASDAQ (QLIKE Holm p = 2×10⁻¹²) and makes no difference on NSE (p = 0.81).
    - ω = 0.25 beats ω = 1 inside the MLP in both markets (QLIKE Holm p ≤ 6×10⁻⁴), the same direction as the pre-registered H2. Neither beats linear GHAR.
  - **Limitation:** one fixed architecture was trained, without a hyper-parameter search. These results show that this nonlinear model adds nothing; they do not show that no network could.
* **Conclusion of the tuning study:** across linear, regularised, tree and neural-network models, **linear GHAR (NASDAQ) or a simple combination (NSE) is the best achievable out-of-sample forecast**. Quantum-walk features add no value in any model class.

## 3c. GPU acceleration of the quantum-walk simulations (`13_gpu_benchmark.R`, fig8)

Random kNN graphs (k = 4). Each timing is the median of 3 runs (2 runs for N ≥ 1600) and computes the walk distributions for all N start nodes.
GPU: RTX 4060 Laptop, torch for R 0.17 with CUDA. Accuracy is measured against torch CPU float64.

| N (arcs) | Method | base R f64 | torch CPU f64 | CUDA f64 | CUDA f32 | f32 max error |
|---|---|---|---|---|---|---|
| 800 (4,080) | CTQW | 4.22 s | 0.195 s | 0.146 s | 0.019 s | 1.4×10⁻⁶ |
| 1600 (8,152) | CTQW | 62.3 s | 0.804 s | 0.961 s | **0.145 s** | 6.8×10⁻⁷ |
| 3200 (16,210) | CTQW | — | 5.62 s | 7.04 s | **0.466 s** | 1.2×10⁻⁶ |
| 800 (4,080) | DTQW | — | 0.976 s | 1.54 s | 0.092 s | 1.9×10⁻⁸ |
| 1600 (8,152) | DTQW | — | 8.68 s | 11.8 s | **0.572 s** | 2.0×10⁻⁸ |

* **CUDA float32** is the fast path:
  - CTQW at N = 1600 is 430× faster than base R and 5.5× faster than optimised torch CPU; at N = 3200 it is 12× faster than torch CPU.
  - DTQW at N = 1600 is 15× faster than torch CPU.
  - The largest float32 error over all sizes is 1.5×10⁻⁴ (CTQW, N = 400). It is far below the precision the features need.
* **CUDA float64 is not faster than the CPU** on this consumer GPU (218 GFLOP/s in f64 vs 7.6 TFLOP/s in f32). This is a hardware limitation to state plainly.
* Below about 200 nodes the GPU has no advantage; launch overhead dominates. The study's own graphs have 20 nodes per market, so the experiments ran on the CPU. The GPU matters for scaling to larger universes (thousands of stocks).
* Excluded by design: base R beyond N = 1600 (impractical), and dense DTQW at N = 3200 (a 16,210² operator).

## 4. Overall conclusion

Quantum coherence measurably changes how a walk diffuses over the market graph. On NASDAQ, an intermediate level of coherence produces slightly better volatility features than the classical limit of the same walk.
But **no quantum-walk feature set improves on simple classical baselines**:
- the naive predictor, for direction;
- linear graph-HAR, for volatility.

The evaluation could detect weak signals (power analysis), so this is an informative negative result about practical quantum advantage, not a failure to look.

## 5. Research question 5 (sentiment): not evaluated

- **RQ5 is not evaluated.** The GDELT DOC 2.0 download ended at its deadline (2026-10-23 12:06) with **21 of 40** tickers. The server rejected requests with HTTP 429 (rate limit), and 7 tickers each failed all 8 retries with back-off.
- Under the precondition in `docs/research/research_questions.md`, partial sentiment data are not used. The chain therefore skipped the sentiment experiment (`results/overnight_chain.log`, 12:23:56).
- The point-in-time sentiment join itself is implemented and validated in Spark against R (agreement 6.5×10⁻⁷ on the decay features, §1). Only the data collection is incomplete.

## 6. Status

All planned experiments are complete. The overnight pipeline, GPU benchmark, GPU MLP (11:51) and Hive reload (09:45) all finished OK on 2026-10-23.
