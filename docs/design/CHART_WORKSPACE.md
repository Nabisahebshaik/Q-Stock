# Design: TradingView-style chart workspace

Status: **implemented 2026-10-25** (verification and limits in §5). Builds on [`DUCKDB_MIGRATION.md`](DUCKDB_MIGRATION.md) (candle store) and the live subsystem in [`DESIGN.md`](DESIGN.md) §3.

## 1. Scope

| In | Out (needs services we do not have) |
|---|---|
| Interval selector 5s, 1m, 5m, 15m, 30m, 1h, 1D, 1W, 1M; range bar 1D 5D 1M 3M 6M YTD 1Y 5Y All | Bar replay, price alerts, order entry ("Trade") |
| Chart types: candles, hollow candles, bars (OHLC), line, area, baseline | Server-side saved layouts |
| Indicators with editable parameters: VWAP (session-anchored), SMA(n), EMA(n), Bollinger(n, k), RSI(n), volume | Pine-style custom scripts |
| Legend: symbol, interval, exchange, O/H/L/C, change; indicator rows with show/hide, settings, remove, more icons | |
| Drawing tools: trend line, ray, horizontal line/ray, vertical line, rectangle, Fibonacci retracement, price-range measure, text; magnet, lock, hide all, remove all, undo/redo; per-ticker persistence in the browser | |
| Screenshot, fullscreen, log/percent scale, exchange clock | |

**Principle unchanged: computation stays in R.** Bars, roll-ups and indicator values come from the API; the UI renders them. Drawings are user annotations (UI state only).

## 2. Data sources per interval

| Interval | Source | Notes |
|---|---|---|
| 5s | Snapshot ticks → `tick_aggregator(5)` in the API, finalised bars upserted to DuckDB with `interval_sec = 5` | Yahoo has no sub-minute bars and there is no free tick feed. While a 5s chart is open the UI polls every 2 s; the API takes at most one Yahoo snapshot per ticker per 2 s (price + cumulative volume; volume per bar = volume delta). Labelled **"snapshot-built"**. Builds only during market hours while watched |
| 1m | Candle store (`interval_sec = 60`) + in-memory forming bar | as `/api/candles` |
| 5m, 15m, 30m, 1h | Roll-up of 1m in DuckDB (`time_bucket` on exchange-local time; open = first, close = last, high = max, low = min, volume = sum) | History = what the store holds (≈ a week locally; less on Render) |
| 1D | Research daily prices + daily Yahoo refresh (30 min cache) + today's bar from the live store | |
| 1W, 1M | Roll-up of 1D in R (weeks start Monday, exchange calendar) | |

Default interval per range (UI): 1D→1m, 5D→5m, 1M…YTD→1D, 1Y→1D, 5Y→1W, All→1W. Any interval/range pair is accepted; the response's `note` says when history is shorter than asked.

## 3. API contract

`GET /api/bars/<market>/<ticker>?interval=1m&range=1D&ind=vwap,sma:20,ema:50,bb:20:2,rsi:14`

* `interval` ∈ {5s, 1m, 5m, 15m, 30m, 1h, 1d, 1w, 1mo} (default 1m); `range` ∈ {1D, 5D, 1M, 3M, 6M, YTD, 1Y, 5Y, ALL} (default 1D).
* `ind`: comma list, at most 8; `vwap`, `sma:<n>`, `ema:<n>`, `bb:<n>:<k>`, `rsi:<n>`; n in 2..500, k in 0.5..5. Invalid specs → HTTP 400.
* Indicators are computed on bars **including warm-up history before the range start** when available, then trimmed to the range; points without a value are omitted.

```json
{
  "market": "NSE", "ticker": "RELIANCE.NS", "label": "RELIANCE", "name": "Reliance Industries",
  "interval": "1m", "range": "1D", "tz": "Asia/Kolkata", "source": "store",
  "live": true, "as_of": 1792746900, "note": null,
  "bars": [{"time": 1792746900, "open": 1183, "high": 1193.5, "low": 1183, "close": 1193.5, "volume": 1200}],
  "indicators": [
    {"id": "sma:20", "type": "sma", "pane": "price", "params": {"n": 20},
     "lines": [{"name": "SMA 20", "values": [{"time": 1792746900, "value": 1190.2}]}]},
    {"id": "rsi:14", "type": "rsi", "pane": "rsi", "params": {"n": 14},
     "lines": [{"name": "RSI 14", "values": []}]}
  ]
}
```

* `time`: epoch seconds shifted to the exchange's local clock (`epoch + gmtoff`), exactly like `/api/candles`, so the chart shows exchange time. Daily and longer bars use the session date at 00:00 UTC.
* `source` ∈ {"store", "daily", "snapshot_5s"}; `live` = market open and the newest bar is from today's session; `as_of` = newest bar's true epoch.
* Bollinger returns three lines (`BB basis`, `BB upper`, `BB lower`); VWAP one line, reset each session, intraday intervals only (omitted with a note on 1D+).
* Static snapshot build: `scripts/25_export_snapshot.R` writes `bars_<MK>_<TICKER>_<interval>.json` for (1D, 1m) and (1Y, 1d) with the default indicator set `vwap,sma:20,ema:50,bb:20:2,rsi:14`; in snapshot mode the UI offers only those two views and locks indicator parameters.

## 4. UI structure (`web/src/components/chart/`)

```
TradingWorkspace          state: ticker, interval, range, chart type, indicators, scale mode
├── ChartToolbar          symbol picker · interval menu · chart type · Indicators dialog · screenshot · fullscreen · settings
├── DrawingToolbar        (left) cursor modes · drawing tools · magnet · lock · hide · remove all · zoom
├── TradingChart          lightweight-charts: price series, volume band, RSI band, overlays, crosshair → legend
│   ├── ChartLegend       OHLC + change; indicator rows (eye · gear · trash · more)
│   └── drawing manager   series primitives (drawing/)
└── BottomBar             ranges · go-to-date · exchange clock · log / % / auto
```

Data hook `useBars(market, ticker, interval, range, ind)` in `lib/api.ts`: refetch every 2 s for 5s, 60 s for intraday, 30 min for daily; placeholder keeps the previous frame.

## 5. Verification and known limits (2026-10-25)

* Tests: 61 testthat blocks / 357 expectations (indicator known-values, roll-up DuckDB = base R incl. the 2026-11-01 US DST change, 5s aggregator with mocked snapshots), 34 API end-to-end checks, Shiny tests; `tsc -b`, lint (0 errors) and build pass.
* Real data (NSE RELIANCE.NS, Sunday, markets closed): 1m/1D 362 bars in 0.29 s; 5m/5D 369 bars 0.16 s; 1d/1Y 247 bars 0.20 s cached (1.9 s with the daily Yahoo refresh); 1w/5Y 261 bars 0.17 s. Hand cross-checks equal: daily SMA20 1192.59, BB upper 1231.68, 1m VWAP 1180.66, RSI14 77.23.
* Browser check on the locally served build: candles, volume, VWAP/SMA/EMA overlays, Bollinger, RSI band, legend values, Indicators dialog, range switch, trend-line drawing and its persistence across reloads.
* Snapshot: `scripts/25_export_snapshot.R` writes `bars_<MK>_<TICKER>_{1m,1d}.json` (80 files); snapshot total 211 files, 12.3 MB.

Limits:
* **5s bars are snapshot-built** (Yahoo has no sub-minute data and no free tick feed): they accumulate only during market hours while a 5s chart is open, the first snapshot of a ticker has volume 0, and the state resets on API restart. Not yet observed live (built and tested on a weekend with mocked snapshots).
* lightweight-charts 4 has no separate panes: RSI and volume are bands of the main chart, so the price axis labels continue into those bands; the RSI value is shown in the legend and on the axis tag. Moving to lightweight-charts 5 panes would fix this.
* Intraday history is what the candle store holds (about a week locally, less on Render after a restart).
* Drawings: no per-drawing style editing; text uses a prompt dialog; touch dragging untested on a device.
* `npm run build` reads `web/.env.production` (Render URL). To serve the UI from a local API use `VITE_API_URL= npm run build`.
