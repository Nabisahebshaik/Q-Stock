---
name: r-plumber-react-dashboard
description: Build and extend the Q-Stock serving layer - an R plumber REST API that keeps all computation in R, a React 18 + TypeScript + Vite + three.js web UI that only renders API responses (TanStack Query, react-three-fiber 3D graph, lightweight-charts candles, recharts), a static JSON snapshot with live fallback, and the R Shiny/bslib dashboard. Use when adding an endpoint, page, chart or snapshot file, or debugging the UI, CORS, caching or blank charts.
---

# R plumber API + React UI + Shiny

## Principle

**Computation stays in R.** The UI never re-implements maths. One contract, four places that must change together:

1. `api/plumber.R` (endpoint, `#* @get`, `unboxedJSON list(na = "null", digits = NA)`)
2. `web/src/lib/api.ts` (TypeScript interface + `useX` TanStack Query hook using `load(livePath, snapshotFile)`)
3. `scripts/25_export_snapshot.R` (writes the same payload to `web/public/data/<file>.json`)
4. `tests/test_api.R` (end-to-end check with the mocked fetcher)

## API patterns (`api/plumber.R`)

- Startup sources `R/*.R`, loads prices and the GHAR model once into globals; root via `options(qstock.root)`.
- Shared `CACHE` env: live 55 s, forecast 30 min, dial per (market, date, ω); limits ω = 0/1 cached per date; precomputed dial JSON served when its date matches.
- Bad input → condition class `qs_bad_request` → HTTP 400; other errors 500 with `{error}`.
- `pr_hooks`: `Server-Timing` on every response; `Cache-Control` immutable for `/assets/*`, `no-cache` for `index.html`.
- `pr_filter("cors")`: `Access-Control-Allow-Origin: *`, GET/OPTIONS only (read-only API).
- Serves `web/dist` statically; a `no_dirs` filter returns 404 for directory paths (plumber's static handler hangs on them).
- Run: `Rscript api/run_api.R [port]`; reads `PORT`, `QSTOCK_HOST`.

## Web UI (`web/`)

- Pages: `LivePage`, `DialPage`, `ResearchPage`, `PipelinePage`; components `QuantumGraph3D` (r3f + d3-force-3d + postprocessing), `CandleChart` (lightweight-charts), `ui.tsx`.
- Modes: `VITE_SNAPSHOT=1` (static), `VITE_API_URL=<remote>` (live with snapshot fallback, fires `qstock-fallback` so pages show a notice), neither (same-origin API).
- Polling via `refetchInterval` (disabled in snapshot mode); `placeholderData: (p) => p` keeps the previous frame during refetch.
- Recharts: disable entry animation (`isAnimationActive={false}`) — animated series rendered blank.
- After a redeploy, hashed chunks of an old page 404: `App.tsx` reloads once (sessionStorage guard).
- Check: `npx tsc -b`, `npm run lint`; screenshots `scripts/24_web_screenshots.R`.

## Shiny (`app/app.R`)

bslib `page_navbar` with `nav_panel`s (Overview, Live market, Quantum dial, Volatility forecasts, Results, Big Data pipeline, System health); plotly, visNetwork, DT; `?tab=Live%20market` deep links. Server tests: `Rscript tests/test_app.R`. Screenshot: `scripts/22_dashboard_screenshot.R` (chromote + Edge).
