---
name: free-tier-r-deployment
description: Deploy an R plumber API as a free Docker web service on Render (Blueprint render.yaml, rocker/r-ver image) and a Vite React UI on Vercel with a live mode against the API and a bundled static snapshot as fallback while the free container sleeps. Includes the free-tier performance fixes (single BLAS thread, no HTTP health check, precomputation). Use when changing deploy/, render.yaml, web/vercel.json, web/.env.production or diagnosing slow or restarting deployments.
---

# Free-tier deployment: Render (R API) + Vercel (UI)

Live: UI https://q-stock-pink.vercel.app · API https://q-stock-api.onrender.com (`/__docs__/`).

## Render (API)

- `render.yaml`: `type: web`, `runtime: docker`, `plan: free`, `region: singapore`, `dockerfilePath: ./deploy/render/Dockerfile`, `dockerContext: .`, `autoDeploy: true`.
- Dockerfile: `rocker/r-ver:4.4.2`; system libs (curl, ssl, sodium, zlib); `install2.r plumber duckdb RSQLite DBI curl jsonlite Matrix`.
- Copy **only** what the API needs: `R/`, `api/plumber.R`, `api/run_api.R`, `api/model`, `api/precomputed`, `results/tables`. No raw/curated data (licence + size). Prices download at build (`|| true` so a Yahoo hiccup does not fail the build; start-up retries).
- `ENV OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1` — on 0.1 CPU, 8 BLAS threads made a 20-node QSW take 39 s; single-threaded 2.0 s.
- **No HTTP health check**: the single-threaded R server could not answer it during a long computation and Render restarted it.
- Precompute expensive views (`api/precomputed/dial_*.json` for the latest date, ω step 0.05) and use exact closed forms where available.
- Free tier sleeps after 15 min idle; first request takes a cold start. Measured: quotes ~11 s, graph ~6 s, forecast ~5 s, dial 0.1–4 s, ~230 MB of 512 MB.

## Vercel (UI)

- `web/vercel.json`: framework vite, `npm ci`, `npm run build:vercel`, output `dist-vercel`; headers: `/assets/*` immutable 1 year, `/data/*` 5 min.
- `scripts/vercel-build.mjs`: live build if `VITE_API_URL` is set (Vercel env var or `web/.env.production`), otherwise snapshot build. Both include `public/data` for fallback.
- `VITE_API_URL` is public (the browser calls it); never put secrets in `VITE_*`.

## Release checklist

1. `Rscript tests/run_tests.R`, `Rscript tests/test_api.R`, `cd web && npx tsc -b`.
2. Refresh snapshot + precomputed dial: `Rscript scripts/25_export_snapshot.R`; GHAR coefficients: `Rscript scripts/26_export_ghar_coef.R`.
3. Commit and push `main` (only when the user asks) → Render and Vercel build automatically.
4. Verify: `curl -I https://q-stock-api.onrender.com/api/status` (look at `Server-Timing`), open the site, confirm the snapshot notice disappears once the API wakes.

Hugging Face Docker Spaces need a paid plan since mid-2026; `deploy/hf-space` + `scripts/27_build_hf_space.sh` are kept for PRO users.
