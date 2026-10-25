---
name: duckdb-parquet-storage
description: Design, migrate and benchmark Q-Stock's columnar storage from R - a DuckDB live-candle store with idempotent upsert and a single-writer rule, Hive-partitioned Parquet history with partition pruning, a bit-identical Parquet cache of the daily research prices, SQLite as a rollback backend, version-portable duckdb drivers for Docker images, and engine benchmarks (SQLite vs DuckDB vs Parquet). Use for R/store_duckdb.R, the store parts of R/data_adapter.R, scripts 29-31, data/live/ or data/curated/, or storage latency questions.
---

# DuckDB + Parquet storage (R)

Design and measured results: `docs/design/DUCKDB_MIGRATION.md` (decision D14 in `docs/design/DESIGN.md`).

## Layout

| Data | Store | Code |
|---|---|---|
| Live 1-min (and snapshot-built 5 s) candles, hot window | `data/live/candles.duckdb` (API), `candles_app.duckdb` (Shiny) | `duck_store_open/upsert/read/stats` in `R/store_duckdb.R` |
| Older live candles | `data/live/parquet/interval_sec=60/day=YYYY-MM-DD/*.parquet` (ZSTD) | `duck_export_parquet()`, read via `duck_read(..., parquet_dir)` |
| Daily research prices cache | `data/curated/prices.parquet` (from `data/raw/prices_yahoo.csv`) | `write_/read_prices_parquet()` in `R/data_adapter.R` |
| Rollback | `data/live/candles.sqlite` | `options(qstock.store_backend = "sqlite")` |

Everything under `data/` is git-ignored. Live data never enters research datasets.

## Rules

- **Same contract, switchable backend.** Callers use `candle_store_open/upsert/read`; the backend dispatches on `qstock.store_backend` (default `duckdb`). Tests run on both.
- **Single writer per DuckDB file.** One read-write process per file, so API and Shiny use different files. Close with `DBI::dbDisconnect(con, shutdown = TRUE)` to release the lock immediately. Keep one long-lived connection in the API (opening costs ≈ 19 ms).
- **Idempotent upsert.** PK (ticker, interval_sec, bucket_start), OHLC `CHECK`, `INSERT … SELECT … ON CONFLICT DO UPDATE` from a registered data frame. **De-duplicate keys first**: DuckDB refuses to update one row twice in a command.
- **Parquet export is whole-day and re-runnable** (`OVERWRITE_OR_IGNORE`), deletes exported rows from DuckDB. DuckDB files do not shrink after DELETE, so script 29 compacts afterwards (`COPY FROM DATABASE`, keeps schema and constraints).
- **Research reproducibility.** The prices Parquet must be `identical()` to the CSV-loaded frame (double-backed Date, plain data.frame, automatic row names). `load_market_data()` uses Parquet only when present and newer than the CSV. Writes go to a temp file then rename, so a reader never sees a partial file.
- **Small containers.** `SET memory_limit = '128MB'`, `threads = 1` on the 512 MB Render instance.
- **Driver portability.** Always connect through `duck_drv(path)`: it passes `shared_home = FALSE` only if the installed duckdb supports it (≥ 1.4; 1.2.0 stops on unknown arguments, which crashed a Render deploy). Docker images pin duckdb 1.5.6 from a dated P3M snapshot with a build-time version check.
- Escape paths inside SQL with `sql_path()`; DuckDB `read_parquet` takes a string literal.

## Scripts

| Script | Does | Verify |
|---|---|---|
| `scripts/29_migrate_sqlite_to_duckdb.R [--export-before-days N]` | SQLite → DuckDB, optional Parquet export | row counts and per-ticker checksums (sum close, min/max bucket) equal |
| `scripts/30_prices_to_parquet.R` | CSV → `prices.parquet` | `identical()` |
| `scripts/31_storage_benchmark.R` | median-of-20 timings, SQLite vs DuckDB vs Parquet | writes `results/tables/storage_benchmark.csv` |

Quote benchmark numbers only from `results/tables/storage_benchmark.csv`. The pattern found: point reads of one session are fast on every engine (HTTP dominates); DuckDB wins as queries grow (multi-session, whole market, aggregates); Parquet suits history and scans, not point reads; the user-visible gain came from serving charts from the store instead of waiting on Yahoo.

## Testing

`tests/testthat/test_store_duckdb.R`, `test_prices_parquet.R`, `test_bars.R` (roll-ups DuckDB = base R); run `Rscript tests/run_tests.R` and `Rscript tests/test_api.R` (cold-store and `days` cases). Point `options(qstock.live_db = ...)` outside OneDrive if sync locks the file.
