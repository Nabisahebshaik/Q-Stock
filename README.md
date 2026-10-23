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
  - On **NASDAQ**, partially decoherent QSW features (ω ≈ 0.25) beat their classical limit (ω = 1). Holm p = 4.8×10⁻⁶ (ω = 0.5: 4.7×10⁻⁸); the result holds under QLIKE, in both halves of the sample and for 17/20 stocks. The fully coherent walk does not.
  - On **NSE**, the classical limit is best.
  - The effect is small and gives no material economic benefit in an inverse-volatility portfolio.
  - A classical linear graph-HAR baseline is as good or better; QSW features add nothing on top of it.

## Layout

```
R/            library: dtqw, ctqw, qsw, market_graph, qsw_features, features, data_adapter,
              sentiment_gdelt, walk_forward, evaluation, dataset, hadoop_bridge, live_market, config
app/          Shiny dashboard, including the Live market tab
tests/        42 testthat blocks, 187 expectations (unitarity, Hermiticity, QSW limits, leakage,
              embargo, live candle store and tick aggregator, ...) + dashboard server tests
scripts/      01–22 numbered pipeline steps; overnight_*.sh orchestration; monitor_system.ps1
hadoop/       Java MapReduce job; VM service start-up and HDFS fix scripts
hive/         HiveQL DDL and queries
docs/         environment report, runbook, CO mapping, research questions, pre-registration,
              novelty audit, literature-survey analysis, results, issues log
paper/        manuscript draft
results/      tables/ (csv + md), figures/ (png), logs, predictions
data/         raw/ (Yahoo, GDELT cache), curated/ (features), synthetic/
```

## Web interface (React + three.js) and R API

- **Live mode:** `Rscript api/run_api.R` serves the R API and the built UI at `http://127.0.0.1:8000`. To build the UI once: `cd web && npm ci && npm run build`.
- **Pages:**
  - Live market: 3D quantum market graph, candlesticks, risk table.
  - Quantum dial: historical QSW, sweeping ω.
  - Research: every headline result, read from `results/tables`.
  - Pipeline.
- **Static snapshot (for Vercel, which cannot run R):** `Rscript scripts/25_export_snapshot.R`, then `cd web && npm run build:snapshot`. `web/vercel.json` builds and serves `web/dist-snapshot`. Every page is labelled with the snapshot time.
- **Live deployment (Vercel + Hugging Face Spaces):**
  1. Build the R API bundle: `Rscript scripts/26_export_ghar_coef.R && bash scripts/27_build_hf_space.sh`. This writes `build/hf-space/`: Dockerfile, R library, API and model coefficients; no raw data. Prices download from Yahoo when the image builds.
  2. Create a Docker Space on huggingface.co and upload the contents of `build/hf-space/`.
  3. Put `VITE_API_URL=https://<user>-<space>.hf.space` in `web/.env.production` (or as a Vercel environment variable) and push. Vercel then builds the live UI.
  - While the free Space is asleep or unreachable, the site falls back to the bundled snapshot with a notice, then switches to live data automatically.
- **Computation stays in R.** The UI only renders API responses.
- **Tests:**
  - `Rscript tests/test_api.R`: 20 end-to-end checks with a mocked feed.
  - `cd web && npx tsc -b`: type check.

## Live market tab (Shiny)

`Rscript -e "shiny::runApp('app', port = 8050, launch.browser = TRUE)"`, then open **Live market** (or go to `http://127.0.0.1:8050/?tab=Live%20market`).
- **Data:** 1-minute bars for the 20 stocks of the selected market, polled every 60 s from the Yahoo chart API (curl multi, about 1–3 s for 20 stocks). It is free and unofficial; NSE bars were observed within seconds of real time, without guarantee.
- **Views:** candlesticks with VWAP and volume (plotly); a live correlation graph of 1-minute returns with the QSW dial (visNetwork); a live risk table with intraday volatility, QSW spillover and a graph-HAR 5-day volatility forecast from completed sessions only.
- **Storage:** the still-forming candle is held in memory (hot). Finalised candles go to SQLite (`data/live/candles.sqlite`, cold) through an idempotent `INSERT … ON CONFLICT DO UPDATE` keyed by (ticker, interval, bucket). The schema and SQL are PostgreSQL-compatible.
- **Tick path:** `tick_aggregator()` handles a future WebSocket feed. It uses event-time buckets, a watermark, duplicate-tick removal and late-tick corrections. It is validated on synthetic and replayed ticks only, because no free tick feed exists.
- **Separation:** live data are for viewing only and never enter the research datasets or results.

## Reproduce

See `docs/runbook.md`. In short:
- run `tests/run_tests.R`
- run `scripts/02` to `16` in order (`03` needs the Cloudera VM; `13` needs an NVIDIA GPU)
- or run `scripts/overnight_v2.sh` for an unattended run
