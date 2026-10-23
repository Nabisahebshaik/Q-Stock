# Hand-off: state of Q-Stock (written 2026-10-22, about 00:15)

Read this first when resuming (a new Claude session or you).

## Running unattended overnight (they do not need Claude)

| Job | Log / output | Done when |
|---|---|---|
| `scripts/overnight_v2.sh`: v1 re-run, naive, ablations, scalability, Spark, Hadoop/Hive, figures | `results/overnight_v2.log` | line `overnight v2 run finished` |
| `scripts/after_overnight_gpu.sh`: GPU benchmark (`13`) + v2 figures (`12`) | same log | line `all overnight work finished` |
| `scripts/after_gpu_mlp.sh`: GPU MLP/QLIKE experiment (`18`), smoke test first | same log | line `gpu mlp work finished` |
| `scripts/overnight_sentiment_chain.sh`: GDELT retries for up to 14 h, then sentiment experiment | `results/overnight_chain.log`, `data/raw/gdelt_cache/` (40 files = complete) | line `done` |
| `scripts/thermal_guard.ps1`: holds all R/java + pauses the VM at GPU ≥ 87 °C or CPU throttling; resumes at ≤ 65 °C | `results/thermal_guard.log` (UTF-16) | runs 14 h |
| `scripts/monitor_system.ps1`: health row every 5 min | `results/system_monitor.csv` | runs 14 h |

## Next steps, in order

1. `grep "===" results/overnight_v2.log`: every step should be `OK`. Re-run any `FAIL` step by hand (`Rscript scripts/<step>.R`) and read its log section.
2. Read the new tables:
   - `v2_mlp_qlike_gpu*.csv`
   - `gpu_benchmark.csv`
   - `ablation_results.csv`
   - `experiment_results.csv` (refreshed to 2026-10-21)
   - `power_analysis_summary.csv`
3. Write `docs/results.md` (final, v1 + v2). The current numbers are in `docs/results_v2.md`; the v1 numbers there must be refreshed from the re-run.
4. If GDELT completed (40 files): check `results/overnight_chain.log` for the sentiment experiment and add RQ5. Otherwise report RQ5 as not evaluated.
5. Rewrite `paper/manuscript_draft.md` with the audit framing (see its header note). Resolve every **[VERIFY]**.
6. Optionally re-run `scripts/03_hadoop_hive.R` with the VM up, to load the refreshed results into Hive.
7. Launch the dashboard: `Rscript -e "shiny::runApp('app', port = 8050, launch.browser = TRUE)"`. Server tests: `Rscript tests/test_app.R`.

## Added after midnight

- `20_tuned_models.R` (nested validation: adaptive ω, elastic net, combination) and `21_lightgbm_nested.R`.
  - Linear GHAR (NASDAQ) or a combination (NSE) is the best achievable forecast.
  - No tuned or nonlinear model beats GHAR significantly, and QSW features add nothing in any model class.
  - Recorded in `docs/results.md` §3b.
- Timing integrity: LightGBM finished at 00:09:39 and the scalability benchmark started at 00:09:48, so they did not overlap. v1 RF runtimes (until 23:49) did not overlap the power analysis either.
- The user asked for the paper writing to pause (the references.bib write was declined). Focus on results until asked.

## Key facts so far

- **v1 (direction):** null; no model beats the naive base rate.
- **v2 H2:** NASDAQ ω = 0.25 beats ω = 1 (Holm p = 4.8e-6; ω = 0.5: Holm p = 4.7e-8; robust). NSE: classical is best.
- **GHAR audit:** QSW adds nothing beyond linear graph-HAR, so there is no practical quantum advantage.
- **Power analysis:** the protocol detects return correlations ≥ 0.035–0.05; zero false positives.
- **Thermal rule from the user:** pause at 87 °C, resume at 50–65 °C (implemented in `thermal_guard.ps1`).
- The user gave a free hand to add improvements and prefers quantum-centred work aimed at a Q1 journal. Report findings faithfully; do not tune for significance.

## Update 2026-10-23 (morning)

- The memory-pressure reaper stopped the thermal guard and some waiters around 00:30. The GPU benchmark was frozen until the guard was back, then resumed on AC power at 08:59. It finished OK at 09:03 (`gpu_benchmark.csv`, fig8). `docs/results.md` §3c has the results.
- The thermal guard and health logger were stopped at the user's request; the user is awake and monitoring.
- `scripts/resume_gpu_chain.sh` replaced the stopped waiters. The GPU MLP smoke test passed; the **full MLP run started 09:06**. The duplicate original `after_gpu_mlp.sh` waiter was terminated so that only one MLP run uses the GPU.
- Doc-vs-CSV audit of every headline number, with corrections:
  - NASDAQ H2: ω = 0.25 has Holm p = 4.8e-6. The 4.7e-8 figure belongs to ω = 0.5. Fixed in results.md, results_v2.md and the manuscript draft.
  - Economic value: the NSE realised-risk difference is significant but negligible (0.015 pp of volatility). It is now reported; it was previously omitted.
  - H1 wording on NASDAQ; NASDAQ GHAR vs HAR p = 5.5e-4.
- Tests: 145/145 pass; the dashboard server tests pass.
- Hadoop VM resumed from the saved state; Hive reload finished OK at 09:45: 5,680 MR groups match R (max error 1.8e-15); the Hive consistency query has 0 mismatches (`results/hive_reload_20261023.log`).
- Remaining: the MLP results go into results.md; RQ5 depends on GDELT (17/40). Next feature after that, agreed with the user: a **Live market tab** in the dashboard (delayed Yahoo intraday data, candlesticks, live correlation graph, live QSW dial).

## Live market tab (2026-10-23, late morning)

- Built in R, the user's choice of "best version". It was chosen over a Python/Redis/PostgreSQL/Docker design because it fits the R-only course rule, needs no paid tick feed and no Docker, and keeps memory headroom next to the Hadoop VM.
- `R/live_market.R`:
  - exchange sessions (DST-aware);
  - Yahoo 1-minute polling via curl multi;
  - hot/cold candle store: in-memory active candle plus SQLite with an idempotent upsert (PostgreSQL-compatible SQL);
  - event-time tick aggregator (watermark, duplicates, late corrections);
  - live graph, QSW features and a graph-HAR forecast from completed sessions.
- `app/app.R`: new "Live market" tab; `?tab=` URL selection. `scripts/22_dashboard_screenshot.R` (chromote + Edge).
- Verified on real NSE data at 11:16–11:24 IST:
  - 20/20 stocks in 0.6–3 s; newest bar 2–19 s old;
  - 2,560 candles stored, 0 rejected; replay idempotent;
  - screenshot `results/screenshots/live_market_tab.png`.
- Bugs found and fixed during the build:
  - flush/prune ordering in the aggregator;
  - all-rejected upsert;
  - a node render before the stock input existed;
  - VWAP starting at 0 on the zero-volume opening bar;
  - an uninformative "centrality" measure, replaced by q_self/q_ent/q_volspill.
- Tests: 42 blocks, 187 expectations, all pass, plus dashboard tests with mocked fetchers.

## Close-out (2026-10-23, midday)

- **GPU MLP: closed.** Finished 11:51 (164 min). `scripts/23_mlp_vs_linear.R` compares it on identical rows: it ties linear GHAR on NASDAQ QLIKE (p = 0.78), is worse on NSE (Holm p = 0.001), and is far worse on MSE (upward bias of about 0.8 log points). See results.md §3b.
- **GDELT / RQ5: closed as not evaluated.** 21/40 tickers at the 12:06 deadline (HTTP 429); sentiment steps skipped by design. See results.md §5.
- **New web UI:**
  - `web/` (React + three.js + TradingView charts), served by the R API in `api/` (plumber).
  - Tests: `tests/test_api.R`, 20 end-to-end checks, offline.
  - Static snapshot for hosting without R: `scripts/25_export_snapshot.R` → `web/public/data`, then `npm run build:snapshot` → `web/dist-snapshot`. `web/vercel.json` deploys it.
- **Doc corrections in this pass:** Spark timing (4.8 s, re-run), the MSE p-value bound for the MLP, README p-value pairing.
- **Next:** git push (the user signs in) and the Vercel deployment of the snapshot UI.

## Live deployment (2026-10-23, evening)

- **Public site:** https://q-stock-pink.vercel.app (Vercel, built from GitHub `main`, live mode via `web/.env.production`).
- **R API:** https://q-stock-api.onrender.com (Render free Docker web service from `render.yaml`; endpoints listed at `/__docs__/`).
- If the API sleeps (15 min idle) or is unreachable, the site shows the bundled snapshot with a notice and switches back to live data automatically.
- Hugging Face Docker Spaces were not used: they need a paid plan since mid-2026.
- **Free-tier findings, fixed:**
  - The HTTP health check restarted the single-threaded R server during long computations (removed).
  - OpenBLAS started 8 threads on a 0.1-CPU container; a 20-node QSW walk took 39 s. With `OPENBLAS_NUM_THREADS=1` it takes 2.0 s.
  - The dial is cached and precomputed for the latest date; the exact limits at ω = 0 and 1 are used.
- **Measured on Render:** live quotes about 11 s (fetch plus parse at 0.1 CPU), live graph about 6 s, forecast about 5 s, dial 0.1–4 s. Memory about 230 MB of 512 MB.
