# End-to-end test of the R plumber API with mocked live fetchers (no network, any time of day)
# and an in-memory candle store. Starts the API in a background R process on a spare port.
#   Rscript tests/test_api.R
port <- as.integer(Sys.getenv("QS_TEST_PORT", "8785"))   # 8765 is used by the web mock server
root <- normalizePath(".")
srv <- callr::r_bg(function(root, port) {
  setwd(root)
  mock_intraday <- function(symbols, interval = "1m", range = "1d") {
    set.seed(1)
    end <- as.numeric(as.POSIXct("2026-10-22 09:00:00", tz = "UTC"))   # 14:30 IST: inside one NSE session
    ts <- as.POSIXct(end - 60 * (149:0), origin = "1970-01-01", tz = "UTC")
    f <- cumsum(rnorm(length(ts), 0, 8e-4))
    data <- lapply(setNames(symbols, symbols), function(s) {
      close <- 100 * exp(f * runif(1, 0.5, 1.5) + cumsum(rnorm(length(ts), 0, 6e-4)))
      open <- c(close[1], head(close, -1))
      d <- data.frame(ticker = s, ts = ts, open = open, high = pmax(open, close) * 1.0004,
                      low = pmin(open, close) * 0.9996, close = close, volume = c(0, rpois(length(ts) - 1, 500)))
      attr(d, "meta") <- list(prev_close = 99, price = tail(close, 1), market_time = tail(ts, 1)); d })
    list(data = data, errors = character())
  }
  mock_daily <- function(symbols, market, range = "1y") {
    p <- read.csv(file.path(root, "data/raw/prices_yahoo.csv"), stringsAsFactors = FALSE); p$date <- as.Date(p$date)   # plumber runs in api/
    list(data = p[p$ticker %in% symbols & p$date >= max(p$date) - 400, ], errors = character())
  }
  mock_snapshot <- function(ticker) list(price = 100 + runif(1), time = as.numeric(Sys.time()), volume = round(as.numeric(Sys.time())))
  options(qstock.root = root, qstock.live_fetcher = mock_intraday, qstock.live_daily_fetcher = mock_daily,
          qstock.snapshot_fetcher = mock_snapshot, qstock.live_db = ":memory:")
  plumber::pr_run(plumber::pr("api/plumber.R"), host = "127.0.0.1", port = port, docs = FALSE)
}, args = list(root = root, port = port))
on.exit(srv$kill(), add = TRUE)

base <- sprintf("http://127.0.0.1:%d", port)
get <- function(path) httr::GET(paste0(base, path), httr::timeout(120))
body <- function(r) jsonlite::fromJSON(httr::content(r, "text", encoding = "UTF-8"), simplifyVector = TRUE)
for (i in 1:90) { ok <- tryCatch(httr::status_code(get("/api/status")) == 200, error = function(e) FALSE); if (ok) break; Sys.sleep(1) }
if (!ok) { cat(srv$read_all_error()); stop("API did not start") }
check <- function(cond, what) { if (!isTRUE(cond)) stop("FAILED: ", what, call. = FALSE); cat("ok  ", what, "\n") }

s <- body(get("/api/status"))
check(identical(sort(s$market), c("NASDAQ", "NSE")) && all(sapply(s$tickers, nrow) == 20), "status lists both markets with 20 stocks")

l <- body(get("/api/live/NSE"))
check(nrow(l$quotes) == 20 && all(is.finite(l$quotes$last)) && all(is.finite(l$quotes$change)), "live quotes: 20 finite prices and changes")
check(!"_row" %in% names(l$quotes), "no row-name leak in JSON")
check(l$store$candles >= 20 * 148 && l$store$rejected == 0, "finalised candles stored, none rejected")
n1 <- l$store$candles
check(body(get("/api/live/NSE"))$store$candles == n1, "second call served from the shared cache (no duplicate writes)")

cd <- body(get("/api/candles/NSE/RELIANCE.NS"))$candles
check(nrow(cd) == 150 && all(cd$high >= pmax(cd$open, cd$close)) && all(cd$low <= pmin(cd$open, cd$close)), "candles are OHLC-consistent")
check(is.na(cd$vwap[1]) && all(is.finite(cd$vwap[-1])), "VWAP undefined before the first traded volume, finite after")
check(all(diff(cd$time) == 60), "candle times on a one-minute grid")
check(identical(body(get("/api/candles/NSE/RELIANCE.NS?days=3"))$candles, cd) &&
      identical(body(get("/api/candles/NSE/RELIANCE.NS?days=x"))$candles, cd), "days: one mocked session; bad value falls back to 1")
cn <- body(get("/api/candles/NASDAQ/NVDA"))$candles                                       # store empty for NASDAQ: one fetch
check(nrow(cn) == 150 && body(get("/api/live/NASDAQ"))$store$candles >= 20 * 148, "cold store: first chart request fills it")

# ---- /api/bars (chart workspace contract, docs/design/CHART_WORKSPACE.md §3) ----
lv <- function(b, id, j = 1) b$indicators$lines[[match(id, b$indicators$id)]]$values[[j]]
b1 <- body(get("/api/bars/NSE/RELIANCE.NS"))
check(b1$interval == "1m" && b1$range == "1D" && b1$source == "store" && b1$tz == "Asia/Kolkata" && b1$label == "RELIANCE" &&
      identical(b1$bars$time, cd$time) && identical(b1$bars$close, cd$close), "bars default 1m/1D = the candle store session")
check(is.list(b1$indicators) && length(b1$indicators) == 0 && is.null(b1$note) && b1$as_of == max(cd$time) - 19800,
      "bars: no indicators asked, note null, as_of = newest bar's true epoch")
b5 <- body(get("/api/bars/NSE/RELIANCE.NS?interval=5m&range=1D&ind=vwap,sma:5"))
grp <- (cd$time - 33300) %/% 300                                                  # 09:15-aligned 5-minute buckets (local clock)
check(nrow(b5$bars) == length(unique(grp)) && nrow(b5$bars) == 31 && all(b5$bars$time %% 300 == 0) &&
      isTRUE(all.equal(b5$bars$volume, as.numeric(tapply(cd$volume, grp, sum)))) &&
      isTRUE(all.equal(b5$bars$high, as.numeric(tapply(cd$high, grp, max)))) &&
      isTRUE(all.equal(b5$bars$close, as.numeric(tapply(cd$close, grp, function(x) x[length(x)])))), "5m roll-up of the 1m bars")
check(nrow(lv(b5, "vwap")) == 31 && nrow(lv(b5, "sma:5")) == 27, "5m: VWAP on every bar, SMA 5 from the 5th")
bd <- body(get("/api/bars/NSE/RELIANCE.NS?interval=1d&range=1Y&ind=sma:20,rsi:14,bb:20:2,ema:50"))
r14 <- lv(bd, "rsi:14")$value
check(bd$source == "daily" && nrow(bd$bars) > 230 && nrow(bd$bars) < 270 && all(bd$bars$time %% 86400 == 0) &&
      all(bd$bars$high >= pmax(bd$bars$open, bd$bars$close)), "1d/1Y: about a year of daily bars at 00:00 UTC")
check(nrow(lv(bd, "sma:20")) == nrow(bd$bars) && length(r14) == nrow(bd$bars) && all(r14 >= 0 & r14 <= 100) &&
      nrow(lv(bd, "ema:50")) == nrow(bd$bars), "indicators warmed up on earlier history: a value on every bar")
check(isTRUE(all.equal(tail(lv(bd, "sma:20")$value, 1), mean(tail(bd$bars$close, 20)), tolerance = 1e-6)), "SMA 20 = mean of the last 20 closes")
bb <- bd$indicators$lines[[match("bb:20:2", bd$indicators$id)]]
check(identical(bb$name, c("BB basis", "BB upper", "BB lower")) && all(bb$values[[2]]$value >= bb$values[[3]]$value), "Bollinger: three lines")
check(identical(bd$indicators$pane, c("price", "rsi", "price", "price")), "indicator panes")
bv <- body(get("/api/bars/NSE/RELIANCE.NS?interval=1d&range=1M&ind=vwap,sma:20"))
check(identical(bv$indicators$id, "sma:20") && grepl("VWAP", bv$note), "VWAP omitted on daily bars, with a note")
bw <- body(get("/api/bars/NSE/RELIANCE.NS?interval=1w&range=5Y"))
check(nrow(bw$bars) > 250 && nrow(bw$bars) < 265 && all(weekdays(as.Date(bw$bars$time / 86400)) == "Monday"), "1w/5Y: weekly bars start Monday")
check(httr::status_code(get("/api/bars/NSE/RELIANCE.NS?ind=sma:1")) == 400 && httr::status_code(get("/api/bars/NSE/RELIANCE.NS?ind=foo")) == 400 &&
      httr::status_code(get("/api/bars/NSE/RELIANCE.NS?interval=2m")) == 400, "invalid indicator or interval -> 400")
check(httr::status_code(get("/api/bars/NSE/AAPL")) == 400 && httr::status_code(get("/api/bars/XYZ/AAPL")) == 400, "unknown ticker or market -> 400")
b5s <- body(get("/api/bars/NSE/RELIANCE.NS?interval=5s&ind=vwap"))
check(b5s$source == "snapshot_5s" && is.list(b5s$bars) &&
      (if (isTRUE(b5s$live) || grepl("snapshot-built", b5s$note)) TRUE else grepl("market closed", b5s$note)), "5s path answers (note set when closed)")

g <- body(get("/api/graph/NSE?omega=0.25&look=120"))
P <- g$P
check(g$n_bars == 120 && length(g$nodes$id) == 20 && all(abs(rowSums(P) - 1) < 1e-4), "graph: 120 returns, 20 nodes, row-stochastic P")
g1 <- body(get("/api/graph/NSE?omega=1&look=120"))
check(max(abs(g1$nodes$q_self - g$nodes$q_self)) > 1e-6, "omega changes the walk")
check(body(get("/api/graph/NSE?omega=7&look=5"))$omega == 1, "out-of-range parameters are clamped")

f <- body(get("/api/forecast/NSE"))
check(isTRUE(f$available) && nrow(f$forecasts) == 20 && all(f$forecasts$vol5_ann > 0 & f$forecasts$vol5_ann < 3), "GHAR forecast for all 20 stocks")

d <- body(get("/api/dial?market=NASDAQ&date=2026-10-20&omega=0.25"))
check(d$date <= "2026-10-20" && all(abs(rowSums(d$P_classical) - 1) < 1e-4) && all(abs(rowSums(d$P_quantum) - 1) < 1e-4), "dial: valid distributions for both limits")

r <- body(get("/api/results"))
check(nrow(r$dial_curve) > 0 && nrow(r$tuned) > 0 && nrow(r$gpu) > 0, "results tables served")

check(httr::status_code(get("/api/live/XYZ")) == 400, "unknown market -> 400")
if (dir.exists("web/dist")) {
  check(httr::status_code(get("/")) == 200, "web UI served at /")
  check(httr::status_code(get("/assets/")) == 404, "directory path -> 404 (no hang)")
  check(httr::status_code(get("/api/status")) == 200, "API still responsive after the directory request")
}
cat("API tests passed\n")
