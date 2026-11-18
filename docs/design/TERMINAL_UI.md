# Terminal UI, sign-in, explainable forecast, news and assistant (2026-11-18)

Added after reviewing a classmate-style "Stock Trends" app (FastAPI + Next.js). Q-Stock took its feature ideas but not its shortcuts. Stock Trends showed template news headlines, hardcoded market panels and synthetic prices as "real-time". In Q-Stock every number on screen comes from an R computation or a CSV in `results/tables/`, and anything unavailable is shown as unavailable.

## UI: terminal theme (`web/src/index.css`, `tailwind.config.js`, `App.tsx`)

- Black canvas with amber labels, accents and panel title bars, white figures, square corners and monospace type throughout. The light theme is a paper/print variant.
- **Command line** (`/` focuses it): `<TICKER> [GP|EXPL|N]`, `DIAL`, `RES`, `PIPE`, `ASK <question>`, `HELP`. A line ending in `?` goes to the assistant.
- **Function keys**: F1 Live, F2 Explain (XAI), F3 News, F4 Quantum dial, F5 Research, F6 Pipeline, F8 assistant.
- **Header and footer**: exchange clocks in the header; the bottom status bar shows the feed in use for each market (`/api/feeds`).
- The selected stock is shared across Live, Explain and News.

## Sign-in (`R/auth.R`, `scripts/32_create_user.R`)

- **Accounts**: `data/auth/users.json` (git-ignored), with scrypt password hashes (libsodium, already a plumber dependency). A container can instead use the `QSTOCK_AUTH_USERS` environment variable; `--print-env` prints its value.
- **Sessions**: a random 256-bit bearer token held in memory for 12 hours. Five failed attempts lock the user name for 10 minutes. The UI stores the token in `localStorage`.
- **Endpoints**:
  - `GET /api/auth/config`
  - `POST /api/auth/login`
  - `GET /api/auth/me`
  - `POST /api/auth/logout`
- **What sign-in protects**: only `/api/chat` needs it. Data endpoints stay public because the static snapshot must work without a server. The UI shows the sign-on screen first; guests get read-only access.
- **No accounts on the server**: sign-in is off, and the UI shows how to create the first account.

## Explainable forecast (`R/explain.R`, `GET /api/explain/<market>/<ticker>`)

The live forecast is the linear graph-HAR model, so its explanation is exact:

pred_i − mean(pred) = Σ_j b_j (x_ij − mean_j x_j)

- **Background**: today's cross-section, so the comparison is against the average stock.
- **Vol-scale factor**: each term multiplies the forecast by exp(c_j / 2), and the factors multiply to the gap.
- **Self-check**: the endpoint returns `check_sum` (≈ 1e-15).
- **Research SHAP**: the endpoint also serves the research model's mean |SHAP| (`explainability_shap.csv`) for the QSW features.
- **Labelling**: the live model is the classical GHAR baseline, and the page says so.

## News (`R/news_feed.R`, `GET /api/news/<market>/<ticker>`)

- **Sources**: the Yahoo Finance search endpoint (headline, publisher, link, time), with the GDELT DOC article list only when Yahoo returns nothing.
- **Caching**: 10 minutes. On failure the last good list is shown, flagged stale.
- **Cleaning**: duplicate titles are dropped.
- **No sentiment scores**: headlines are shown without scores, and no headline is generated.
- **No tweets**: Yahoo has no social-post feed, and the X API became pay-per-use in Feb 2026, so tweets were left out at the user's request.

## Assistant (`R/assistant.R`, `POST /api/chat`)

- **How it answers**: deterministic, in R, with no external language model. It finds the stock (symbol, full name or a distinctive first word) and the intent: explain, forecast, quote, news, results, quantum, help or advice.
- **Data sources**: the same functions as the endpoints (`live_payload`, `forecast_state`, `explain_state`, `news_state`) and `results/tables`.
- **Sources and limits**: every reply lists its sources. It says "not available" instead of estimating, and declines buy/sell advice.
- **Results summary**: built from `v2_hypothesis_tests.csv` per market and loss (counts of Holm-significant settings and the largest significant gain), so it changes with the CSV.

## Kotak Neo feed

See `docs/operations/KOTAK_NEO.md`. `fetch_intraday_auto()` sends NSE symbols to Kotak when configured and everything else to Yahoo, and records the source of each symbol. The store tags each feed's candles (`kotak_neo_poll` or `yahoo_poll`). `/api/live` quotes carry `feed`.

## Snapshot

`scripts/25_export_snapshot.R` also writes `explain_*`, `news_*` (headlines as of snapshot time) and `feeds.json`. In the snapshot build, sign-in and the assistant are unavailable, and the UI says so.

## Tests

- `tests/testthat/test_features_v4.R` (9 blocks, 84 expectations) covers:
  - hash round-trip; sessions, expiry and lock-out
  - exactness of the explanation
  - Yahoo and GDELT parsers
  - RFC 6238 TOTP vectors
  - Kotak candle and quote parsers
  - feed routing
  - assistant intents and grounded replies
- `tests/test_api.R`: 15 new end-to-end checks (49 in total).
