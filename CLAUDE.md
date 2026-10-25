# Q-Stock: instructions for Claude sessions (Code and Cowork)

Big Data research framework: classically simulated quantum walks (DTQW, CTQW, QSW with a quantum-to-classical dial ω) on NSE/NASDAQ correlation graphs, evaluated for forecasting under a pre-registered, leakage-controlled walk-forward protocol. Course project for SRM University–AP, CSE 465 Principles of Big Data Management, aimed at a Q1 journal.

**Read first:** `docs/README.md` (index) → `docs/architecture/ARCHITECTURE.md` → `docs/design/DESIGN.md`. For current state, the latest section of `docs/operations/HANDOFF.md`.

## Ground rules (from the user; do not relax)

- **All analysis in R.** No Python, no PySpark. Spark only via sparklyr. MapReduce is Java (Hadoop's own language).
- **Classical simulation only.** Never claim quantum hardware or quantum speed-up.
- **Synthetic data only validates software.** No predictive claim rests on it.
- **Report findings faithfully; never tune for significance.** The v2 ω grid {0, 0.1, 0.25, 0.5, 0.75, 0.9, 1}, targets and Holm families are pre-registered (`docs/research/preregistration_v2.md`). Anything else is labelled *exploratory*.
- **Every number in docs must trace to a CSV** in `results/tables/`. After changing results, re-audit docs, README and `paper/manuscript_draft.md` against the CSVs.
- **Live data never enters research datasets.** Live candles go only to `data/live/` (DuckDB + Parquet; SQLite rollback copy).
- **Thermal rule for long GPU/CPU runs:** pause at 87 °C, resume at 50–65 °C (`scripts/thermal_guard.ps1`).
- The user prefers quantum-centred work and gave a free hand for improvements; paper writing is paused until they ask.
- Commit only when asked. Project lives in OneDrive: keep large outputs in git-ignored paths.

## Environment (Windows 11, Lenovo Legion 5, i7-13650HX, 24 GB, RTX 4060 8 GB)

- R 4.6.1 is **not on PATH**: `& "C:\Program Files\R\R-4.6.1\bin\x64\Rscript.exe"` (PowerShell) or `"/c/Program Files/R/R-4.6.1/bin/x64/Rscript.exe"` (Git Bash).
- Run everything from the project root; every entry point sources all of `R/*.R`. Config: `QS` in `R/config.R`, `LIVE` in `R/live_market.R`.
- Java 17 + Spark 3.5.9 for sparklyr (local[8]); Cloudera QuickStart VM 5.13 in VirtualBox for HDFS/MapReduce/Hive (start-up: `docs/operations/runbook.md` §1).
- GPU scripts set `TORCH_CUDATOOLKIT=FALSE`.

## Common commands

| Task | Command |
|---|---|
| Unit tests (42 blocks / 187 expectations) | `Rscript tests/run_tests.R` |
| API end-to-end (offline, mocked feed) | `Rscript tests/test_api.R` |
| Shiny server tests | `Rscript tests/test_app.R` |
| Web type check / lint | `cd web && npx tsc -b` / `npm run lint` |
| API + built UI on :8000 | `cd web && npm ci && npm run build`, then `Rscript api/run_api.R` |
| Web dev server | `cd web && npm run dev` (set `VITE_API_URL` to the API) |
| Shiny dashboard on :8050 | `Rscript -e "shiny::runApp('app', port = 8050, launch.browser = TRUE)"` |
| Static snapshot | `Rscript scripts/25_export_snapshot.R`, then `cd web && npm run build:snapshot` |
| Full pipeline | numbered `scripts/02`–`23` (see runbook), or `scripts/overnight_v2.sh` unattended |
| Storage (DuckDB/Parquet) | `Rscript scripts/29_migrate_sqlite_to_duckdb.R` (SQLite → DuckDB, verify, export old days), `scripts/30_prices_to_parquet.R`, `scripts/31_storage_benchmark.R`; rollback `options(qstock.store_backend = "sqlite")` |

## Layout

`R/` library · `scripts/` numbered pipeline steps + overnight chains · `tests/` · `api/` plumber REST · `app/` Shiny · `web/` React + three.js · `hadoop/` Java MR + VM scripts · `hive/` HQL · `deploy/` Render + HF Space Dockerfiles · `results/` tables, figures, logs · `docs/` · `paper/`.

## Deployment

- UI: https://q-stock-pink.vercel.app (Vercel, `web/vercel.json`, `npm run build:vercel`, live via `web/.env.production`).
- API: https://q-stock-api.onrender.com (Render free Docker from `render.yaml`; docs at `/__docs__/`). Sleeps after 15 min; the UI falls back to the bundled snapshot.
- Keep `OPENBLAS_NUM_THREADS=1` and no HTTP health check on Render (see DESIGN.md D11).

## Conventions

- R style: base R, `<-`, terse one-line helpers, comments explain *why*; functions in `snake_case`; config in `QS`.
- When the API contract changes, update `api/plumber.R`, `web/src/lib/api.ts`, `scripts/25_export_snapshot.R` and `tests/test_api.R` together.
- Long runs: write `=== step OK/FAIL` markers to the log and check R exit status explicitly in shell chains.
- Update `docs/operations/HANDOFF.md` with a dated section at the end of significant work.

## Project skills

`.claude/skills/` holds the workflows used in this project (quantum-walk simulation, leakage-safe evaluation, Hadoop/Hive/Spark, live market pipeline, R API + React UI, free-tier deployment, GPU/long-run safety, results audit). Zipped copies for Cowork upload are produced by `scripts/28_package_skills.ps1`.
