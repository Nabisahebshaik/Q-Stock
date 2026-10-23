---
title: Q-Stock API
emoji: 📈
colorFrom: indigo
colorTo: blue
sdk: docker
app_port: 7860
pinned: false
short_description: R API for live market graphs and quantum-walk analytics
---

# Q-Stock R API

The R back end of the Q-Stock web interface. It serves:
- live 1-minute market data;
- correlation graphs with quantum stochastic walk (QSW) features;
- graph-HAR volatility forecasts;
- the quantum dial;
- research results.

All quantum walks are **classical simulations** in R. Live prices come from the free, unofficial Yahoo chart API; they are for viewing only and are not trading advice.

**Endpoints** (OpenAPI docs at `/__docs__/`):

| Endpoint | Returns |
|---|---|
| `GET /api/status` | exchange sessions and universes |
| `GET /api/live/{NSE\|NASDAQ}` | live quotes, shared one-minute cache |
| `GET /api/candles/{market}/{ticker}` | 1-minute candles with VWAP |
| `GET /api/graph/{market}?omega=0.25&look=120` | live graph with QSW node features |
| `GET /api/forecast/{market}` | graph-HAR 5-day volatility forecast |
| `GET /api/dial?market=NASDAQ&omega=0.25` | historical quantum dial |
| `GET /api/results` | research result tables |

Source: https://github.com/Nabisahebshaik/Q-Stock
