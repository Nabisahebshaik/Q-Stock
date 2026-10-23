# Q-Stock

A Big Data framework for financial forecasting with classically simulated quantum walks on market-state graphs. It covers:
- discrete-time quantum walks (DTQW)
- continuous-time quantum walks (CTQW)
- quantum stochastic walks (QSW) with a quantum-to-classical dial ω

Course project for SRM University–AP, CSE 465 Principles of Big Data Management.

> All quantum walks are **classical simulations** (R on CPU; torch/CUDA for the GPU benchmark). No quantum hardware is used and no quantum speed-up is claimed.
> Synthetic data is used **only** to validate software.

## Headline findings (details: `docs/results_v2.md`, `docs/results.md`)

* **Next-day direction:** no feature set (classical, classical diffusion or quantum walk) beats a naive base-rate predictor in either market.
* **5-day realised volatility (pre-registered primary target):**
  - On **NASDAQ**, partially decoherent QSW features (ω ≈ 0.25) beat their classical limit (ω = 1). Holm p = 4.7×10⁻⁸; the result holds under QLIKE, in both halves of the sample and for 17/20 stocks. The fully coherent walk does not.
  - On **NSE**, the classical limit is best.
  - The effect is small and gives no measurable economic benefit in an inverse-volatility portfolio.

## Layout

```
R/            library: dtqw, ctqw, qsw, market_graph, qsw_features, features, data_adapter,
              sentiment_gdelt, walk_forward, evaluation, dataset, hadoop_bridge, config
tests/        32 testthat blocks (unitarity, Hermiticity, QSW limits, leakage tests, embargo, ...)
scripts/      01–16 numbered pipeline steps; overnight_*.sh orchestration; monitor_system.ps1
hadoop/       Java MapReduce job; VM service start-up and HDFS fix scripts
hive/         HiveQL DDL and queries
docs/         environment report, runbook, CO mapping, research questions, pre-registration,
              novelty audit, literature-survey analysis, results, issues log
paper/        manuscript draft
results/      tables/ (csv + md), figures/ (png), logs, predictions
data/         raw/ (Yahoo, GDELT cache), curated/ (features), synthetic/
```

## Reproduce

See `docs/runbook.md`. In short:
- run `tests/run_tests.R`
- run `scripts/02` to `16` in order (`03` needs the Cloudera VM; `13` needs an NVIDIA GPU)
- or run `scripts/overnight_v2.sh` for an unattended run
