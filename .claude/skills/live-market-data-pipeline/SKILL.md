---
name: live-market-data-pipeline
description: Build or modify the R live-market pipeline - DST-aware exchange sessions (NSE, NASDAQ), 1-minute Yahoo chart polling with curl multi, a hot/cold candle store (in-memory forming candle plus DuckDB idempotent upsert with Parquet history; SQLite rollback backend), an event-time tick aggregator with watermark and late-tick corrections, live correlation graphs with QSW features and a graph-HAR volatility forecast. Use for R/live_market.R, the Shiny Live market tab, or the /api/live, /api/candles, /api/graph and /api/forecast endpoints.
---

# Live market data pipeline (R)

Code: `R/live_market.R` (config list `LIVE`), used by `app/app.R` and `api/plumber.R`. Tests: `tests/testthat/test_live.R`.

## Rules

- Live data are **for viewing only**; they never enter research datasets or results.
- Source: Yahoo chart API (free, unofficial). Poll once per market per minute and **share the batch** across all viewers (server-side cache, 55 s).
- On fetch failure keep the last good batch and flag `stale = TRUE`; never blank the UI.

## Components

| Piece | Function(s) | Notes |
|---|---|---|
| Sessions | `market_status()` | NSE 09:15–15:30 Asia/Kolkata; NASDAQ 09:30–16:00 America/New_York; weekday check in exchange tz. Holidays not modelled → "open by clock, no recent bars" |
| Fetch | `fetch_intraday_many(tickers, "1m", range)` | curl multi, 20 tickers in ~1–3 s locally; range `1d` once 30 min into the session else `5d` |
| Split | `split_active(bars, 60, now, open)` | finalised bars vs the still-forming bar |
| Cold store | `candle_store_open()`, `candle_upsert()`, `candle_read()`, `candle_stats()`, `candle_store_close()` → `duck_*` in `R/store_duckdb.R` | DuckDB `data/live/candles.duckdb` (API) / `candles_app.duckdb` (Shiny; one writer process per file), Parquet history `data/live/parquet/interval_sec=60/day=…`, SQLite via `options(qstock.store_backend = "sqlite")`; PK (ticker, interval_sec, bucket_start), `INSERT … ON CONFLICT DO UPDATE`, OHLC CHECK constraint; replays idempotent |
| Tick path | `tick_aggregator()`, `agg_push/advance/flush/active` | event-time buckets, watermark `grace_sec = 5`, duplicate removal, late corrections within `retention_sec = 3600`. Validated on synthetic/replayed ticks only |
| Analytics | `intraday_returns_wide()`, `live_graph()`, `live_walk()`, `intraday_rv()` | kNN correlation graph of the last `look` 1-min returns, QSW at ω (exact limits at 0/1), features `q_self`, `q_ent`, `q_volspill` |
| Forecast | `ghar_live_model()`, `ghar_live_forecast()` | graph-HAR 5-day vol from **completed** daily sessions; container uses exported coefficients `api/model/ghar_live_model.json` (`scripts/26_export_ghar_coef.R`) |

## Bugs already hit (test for them)

- Flush/prune ordering in the aggregator.
- Upsert where every row is rejected.
- VWAP starting at 0 on a zero-volume opening bar.
- Rendering a node before its input exists (Shiny).
- Uninformative "centrality" measures; use walk features instead.

## Testing

Inject fetchers via options so tests run offline: `qstock.live_fetcher`, `qstock.live_daily_fetcher`, `qstock.live_db`. Run `Rscript tests/run_tests.R`, `Rscript tests/test_api.R`, `Rscript tests/test_app.R`. Verify on real data during market hours: 20/20 stocks, newest bar age in seconds, 0 rejected candles.
