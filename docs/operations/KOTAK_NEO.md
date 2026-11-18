# Kotak Neo live feed (NSE)

Optional. Without it, live NSE prices come from Yahoo as before. With it, the API pulls NSE 1-minute candles and quotes from the Kotak Neo Trade API and falls back to Yahoo per stock if Kotak fails. The feed is used for the live pages only and never enters the research datasets (CLAUDE.md ground rule). The module (`R/kotak_neo.R`) calls only login, scrip master, quotes and historical candles. It has no order functions.

## One-time setup in the Kotak Neo app

1. Open **More → Trade API** and create an application. The token it shows is your **access token**.
2. On the same page, choose **TOTP Registration** and scan the QR code with Google or Microsoft Authenticator.
3. Static-IP whitelisting is needed only for placing orders. Q-Stock never places orders.

## On your laptop

```powershell
Copy-Item .Renviron.example .Renviron   # in the project root; .Renviron is git-ignored
notepad .Renviron                       # fill KOTAK_ACCESS_TOKEN, KOTAK_MOBILE (+91...), KOTAK_UCC, KOTAK_MPIN
& "C:\Program Files\R\R-4.6.1\bin\x64\Rscript.exe" api/run_api.R
```

When `KOTAK_TOTP_SECRET` is empty, `run_api.R` asks for the 6-digit authenticator code at start-up. If you press Enter, NSE stays on Yahoo. When the secret is set, the API generates the code itself (RFC 6238; needs the `openssl` or `digest` R package). The secret is as sensitive as the MPIN, so keep it only in `.Renviron` on your own machine.

Check the result:
- `GET /api/feeds` returns `kotak_neo: "connected"` (or the error message).
- On the Live page, each quote's card says `feed Kotak Neo` or `feed Yahoo`.
- Candles in the store are tagged `kotak_neo_poll`.

The session is reused for 8 hours. With a stored secret it renews itself; without one, restart the API to sign in again.

## How it maps to Q-Stock

| Q-Stock | Kotak Neo v2 |
|---|---|
| ticker `RELIANCE.NS` | scrip master `nse_cm`, `pTrdSymbol = RELIANCE-EQ` → `pSymbol` (cached daily in `data/live/kotak_nse_cm.csv`) |
| 1-minute bars | `GET <baseUrl>/market-data/1.0/historical/details?neosymbol=nse_cm|<token>&interval=1min` |
| previous close, last price | `GET <baseUrl>/script-details/1.0/quotes/neosymbol/nse_cm|<t1>,.../all` (`ohlc.close`, `ltp`) |
| login | `POST mis.kotaksecurities.com/login/1.0/tradeApiLogin` (TOTP), then `tradeApiValidate` (MPIN), which returns `baseUrl` |

Reference: https://github.com/Kotak-Neo/Kotak-Neo/tree/main/docs. The parsers are tested offline against the documented response shapes (`tests/testthat/test_features_v4.R`). The live login has not been run from this repository yet. Run it once on the laptop and record the outcome in HANDOFF.md.

The cloud API (Render) does not use Kotak: its container has no `.Renviron`, and a whitelisted static IP would not apply there anyway.
