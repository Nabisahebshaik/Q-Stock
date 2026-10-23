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
