# Headless test of the Shiny dashboard's server logic (run from the project root):
#   Rscript tests/test_app.R
# The Live market tab is tested with mocked fetchers (no network, any time of day)
# and an in-memory candle store.
library(shiny)

mock_intraday <- function(symbols, interval = "1m", range = "1d") {
  set.seed(1)
  end <- as.numeric(as.POSIXct("2026-10-22 19:00:00", tz = "UTC"))   # 15:00 New York: one session, any test time
  ts <- as.POSIXct(end - 60 * (149:0), origin = "1970-01-01", tz = "UTC")
  f <- cumsum(rnorm(length(ts), 0, 8e-4))
  data <- lapply(setNames(symbols, symbols), function(s) {
    close <- 100 * exp(f * runif(1, 0.5, 1.5) + cumsum(rnorm(length(ts), 0, 6e-4)))
    open <- c(close[1], head(close, -1))
    d <- data.frame(ticker = s, ts = ts, open = open, high = pmax(open, close) * 1.0004,
                    low = pmin(open, close) * 0.9996, close = close, volume = rpois(length(ts), 500))
    attr(d, "meta") <- list(prev_close = 99, price = tail(close, 1), market_time = tail(ts, 1))
    d })
  list(data = data, errors = character())
}
prices_csv <- normalizePath("data/raw/prices_yahoo.csv")   # the app runs with app/ as working directory
mock_daily <- function(symbols, market, range = "1y") {
  p <- read.csv(prices_csv, stringsAsFactors = FALSE); p$date <- as.Date(p$date)
  p <- p[p$ticker %in% symbols & p$date >= max(p$date) - 400, ]
  list(data = p, errors = character())
}
options(qstock.live_fetcher = mock_intraday, qstock.live_daily_fetcher = mock_daily, qstock.live_db = ":memory:")

app <- shinyAppDir("app")
testServer(app, {
  session$setInputs(mk = "NASDAQ", dt = as.Date("2026-10-20"))
  session$setInputs(start = "NVDA", omega = 0.25)
  d <- dist()
  stopifnot(nrow(d) == 20, abs(sum(d$sel) - 1) < 1e-8, abs(sum(d$classical) - 1) < 1e-8)
  stopifnot(any(abs(d$sel - d$classical) > 1e-4))           # dial actually changes the walk
  session$setInputs(omega = 1)
  stopifnot(max(abs(dist()$sel - dist()$classical)) < 1e-10) # omega = 1 equals the classical limit
  session$setInputs(fmk = "NASDAQ", ftick = "NVDA", frange = c(as.Date("2025-01-01"), as.Date("2026-10-20")))
  stopifnot(nrow(fdat()) > 100)
  cat("dashboard server tests passed: walk mass =", sum(d$sel), "; forecast rows =", nrow(fdat()), "\n")

  # Live market tab
  session$setInputs(lmk = "NASDAQ", ltick = "NVDA", llook = 120, lomega = 0.25, lauto = FALSE, lrefresh = 1)
  session$flushReact()
  stopifnot(!is.null(lv$bars), length(unique(lv$bars$ticker)) == 20)
  n1 <- DBI::dbGetQuery(store_con, "SELECT COUNT(*) n FROM candles")$n
  stopifnot(n1 >= 20 * 148)                                  # finalised candles stored
  session$setInputs(lrefresh = 2); session$flushReact()      # same bars again: idempotent upsert
  stopifnot(DBI::dbGetQuery(store_con, "SELECT COUNT(*) n FROM candles")$n == n1)
  g <- lgraph(); w <- lwalk()
  stopifnot(length(g$tick) == 20, g$n_bars == 120, all(abs(rowSums(attr(w, "P")) - 1) < 1e-10),
            all(is.finite(w$q_volspill)))
  stopifnot(length(lchg()) == 20, all(is.finite(lchg())))
  f <- lforecast()
  stopifnot(!is.null(f), nrow(f) == 20, all(f$vol5_ann > 0 & f$vol5_ann < 3))
  session$setInputs(lomega = 1); w1 <- lwalk()
  stopifnot(max(abs(w1$q_self - w$q_self)) > 1e-6)           # omega changes the live walk
  cat("live tab tests passed:", n1, "candles stored (idempotent on replay);", length(g$tick), "nodes;",
      "GHAR forecast for", nrow(f), "stocks as of", format(f$as_of[1]), "\n")
})
