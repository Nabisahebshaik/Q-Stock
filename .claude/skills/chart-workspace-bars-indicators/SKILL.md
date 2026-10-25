---
name: chart-workspace-bars-indicators
description: Extend the Q-Stock TradingView-style chart workspace - the /api/bars endpoint with intervals 5s to 1M (snapshot-built 5 s bars, 1-min store, DuckDB intraday roll-ups on exchange-local time, daily/weekly/monthly roll-ups in R), technical indicators computed in R (VWAP, SMA, EMA, Bollinger, RSI) with warm-up history, and the React lightweight-charts workspace with legend, indicator dialog and drawing tools. Use for R/bars.R, R/indicators.R, the /api/bars endpoint, web/src/components/chart/ or bars_*.json snapshot files.
---

# Chart workspace: bars, indicators, drawings

Spec and verification: `docs/design/CHART_WORKSPACE.md`. Storage underneath: the `duckdb-parquet-storage` skill.

## Principle

**Bars and indicator values are computed in R; the UI renders them.** Drawings are user annotations and the only chart state that lives in the browser (per-ticker, localStorage).

## Contract

`GET /api/bars/<market>/<ticker>?interval=1m&range=1D&ind=vwap,sma:20,ema:50,bb:20:2,rsi:14`

- `interval` ∈ 5s, 1m, 5m, 15m, 30m, 1h, 1d, 1w, 1mo; `range` ∈ 1D, 5D, 1M, 3M, 6M, YTD, 1Y, 5Y, ALL.
- `ind`: at most 8 specs, n in 2..500, k in 0.5..5; anything else → `bad_request()` → HTTP 400 (`parse_ind_spec`).
- `time` = epoch shifted to exchange-local clock (`epoch + gmtoff`), as in `/api/candles`; daily bars at session date 00:00 UTC. `as_of` is the true epoch.
- `source` ∈ store | daily | snapshot_5s; `note` explains short history (`range_note`).
- A contract change touches the usual four places: `api/plumber.R`, `web/src/lib/api.ts` (`useBars`), `scripts/25_export_snapshot.R` (`bars_<MK>_<TICKER>_{1m,1d}.json`), `tests/test_api.R`.

## R side

| Piece | Function(s) | Watch out for |
|---|---|---|
| Intraday roll-up | `rollup_intraday_duck()` (`time_bucket` on exchange-local time), reference `rollup_intraday_r()` | test DuckDB = base R across a DST change (2026-11-01 US) |
| Daily → week/month | `rollup_daily(d, "week"/"month")` | weeks start Monday |
| Ranges | `range_start()`, `months_back()` | Mar 31 − 1 month = Feb 28 |
| 5 s bars | `snapshot_state/tick/bars()` + `tick_aggregator(5)` | Yahoo has no sub-minute data: built from ≤ 1 snapshot per ticker per 2 s while a 5s chart is open, volume = cumulative-volume delta, first bar volume 0, resets on restart. Always label **snapshot-built** |
| Indicators | `sma`, `ema`, `bollinger`, `rsi` (Wilder RMA), `vwap_session`, `compute_indicators()` | compute on bars **with warm-up history before the range**, then trim (`keep`); omit points without a value; VWAP resets per session, intraday only |

Check new indicators against hand-computed known values (`tests/testthat/test_indicators.R`).

## UI side (`web/src/components/chart/`)

`TradingWorkspace` (state) → `ChartToolbar`, `IndicatorsDialog`, `drawing/DrawingToolbar`, `TradingChart` (lightweight-charts 4: price, volume band, RSI band, overlays), `ChartLegend`, `BottomBar`. Drawings: `drawing/manager.ts` + `geometry.ts` as series primitives (trend line, ray, horizontal/vertical, rectangle, Fibonacci, price range, text; magnet, lock, undo/redo).

- Polling: 2 s for 5s, 60 s intraday, 30 min daily; `placeholderData` keeps the last frame.
- lightweight-charts 4 has no panes, so RSI and volume are bands of the main chart; v5 panes would fix the shared price axis.
- Snapshot mode offers only (1D, 1m) and (1Y, 1d) with the default indicator set, parameters locked.
- Local build against a local API: `VITE_API_URL= npm run build` (plain build targets Render).

## Verify

`Rscript tests/run_tests.R`, `Rscript tests/test_api.R`, `cd web && npx tsc -b && npm run lint`, then a browser check of the served build: candles, overlays, RSI band, legend values, range switch, a drawing that survives reload.
