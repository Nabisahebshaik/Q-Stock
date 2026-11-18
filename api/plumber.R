# Q-Stock REST API (R plumber). All computation stays in R; the React UI (web/) only
# renders what these endpoints return.
#   Rscript api/run_api.R          -> http://127.0.0.1:8000  (also serves web/dist)
#
# Live data are fetched once per market per minute on the server and shared by every
# viewer (one Yahoo request batch, not one per browser tab). Live data are for viewing
# only and never enter the research datasets or results.

ROOT <- getOption("qstock.root", normalizePath("."))
local({ old <- setwd(ROOT); on.exit(setwd(old))
  for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f, local = globalenv())
  assign("PRICES", clean_prices(load_market_data())$data, globalenv())
  # Full fit when the curated research data are present; otherwise (cloud container) the
  # exported coefficients of the same fit (scripts/26_export_ghar_coef.R).
  saved <- if (file.exists("api/model/ghar_live_model.json")) jsonlite::fromJSON("api/model/ghar_live_model.json") else NULL
  assign("GHAR_LIVE", lapply(c(NSE = "NSE", NASDAQ = "NASDAQ"), function(mk) {
    m <- ghar_live_model(mk)
    if (is.null(m) && !is.null(saved[[mk]])) m <- list(coef = unlist(saved[[mk]]$coef, use.names = FALSE),
      train_from = as.Date(saved[[mk]]$train_from), train_to = as.Date(saved[[mk]]$train_to), n = saved[[mk]]$n)
    m
  }), globalenv())
})
RW <- lapply(split(PRICES, PRICES$market), returns_wide)
FETCH <- getOption("qstock.live_fetcher", fetch_intraday_auto)   # Kotak Neo for NSE when configured, else Yahoo
FETCH_NEWS <- getOption("qstock.news_fetcher", fetch_news)
FETCH_DAILY <- getOption("qstock.live_daily_fetcher", fetch_daily_many)
STORE <- candle_store_open(getOption("qstock.live_db", file.path(ROOT, if (store_backend() == "duckdb") LIVE$db_path else LIVE$sqlite_path)))
PARQUET <- file.path(ROOT, LIVE$parquet_dir)
CACHE <- new.env()
TAUS <- QS$walk_time * seq_len(10) / 10
AUTH_STORE <- auth_store(auth_read_users(file.path(ROOT, AUTH$users_path)))
KOTAK_LOGIN <- if (kotak_configured()) {
  # Sign in once at start-up: TOTP from the stored secret, or the code typed into run_api.R.
  code <- getOption("qstock.kotak_totp", NULL)
  r <- tryCatch({ kotak_login(code); "connected" }, error = function(e) conditionMessage(e))
  message("Kotak Neo: ", r); r
} else "not configured"
tab <- function(f) { p <- file.path(ROOT, "results", "tables", f); if (file.exists(p)) read.csv(p, check.names = FALSE) else NULL }
check_market <- function(market) {
  if (!market %in% names(QS$universe))
    stop(structure(class = c("qs_bad_request", "error", "condition"), list(message = paste("unknown market:", market), call = NULL)))
  market
}
epoch <- function(x) as.numeric(x)
short <- function(tk) sub("\\.NS$", "", tk)

# ---- shared live cache ----
live_state <- function(mk, max_age = 55) {
  c0 <- CACHE[[mk]]
  if (!is.null(c0) && epoch(Sys.time()) - c0$at < max_age) return(c0)
  st <- market_status(mk); tk <- names(QS$universe[[mk]])
  rng <- if (isTRUE(st$open) && st$minutes_open >= 30) "1d" else "5d"
  t0 <- Sys.time()
  r <- tryCatch(FETCH(tk, "1m", rng), error = function(e) list(data = list(), errors = c(all = conditionMessage(e))))
  if (!length(r$data)) {                               # keep the last good data, flagged as stale
    if (!is.null(c0)) { c0$errors <- r$errors; c0$stale <- TRUE; return(c0) }
    return(list(at = epoch(Sys.time()), bars = NULL, errors = r$errors, stale = TRUE))
  }
  s <- split_active(do.call(rbind, r$data), 60, Sys.time(), st$open)
  out <- list(at = epoch(Sys.time()), bars = rbind(s$final, s$active), n_active = nrow(s$active), active = s$active,
              meta = lapply(r$data, attr, "meta"), errors = r$errors, stale = FALSE, range = rng,
              fetch_sec = as.numeric(difftime(Sys.time(), t0, units = "secs")),
              store = upsert_by_source(s$final, r$source), sources = r$source, walks = new.env())
  CACHE[[mk]] <- out
  out
}

# Finalised candles go to the store tagged with the feed each ticker came from.
upsert_by_source <- function(final, src) {
  if (!NROW(final)) return(candle_upsert(STORE, final, 60, "yahoo_poll"))
  feed <- if (is.null(src)) rep("yahoo", nrow(final)) else unname(src[final$ticker])
  feed[is.na(feed)] <- "yahoo"
  parts <- split(final, feed)
  Reduce(`+`, Map(function(x, f) candle_upsert(STORE, x, 60, paste0(f, "_poll")), parts, names(parts)))
}

# Chart bars: finalised candles from the store plus the forming bar held in memory.
# /api/live is the one place that polls Yahoo; a chart fetches only when the store has
# nothing for the ticker (cold start) or, during the session, is more than 5 minutes behind.
# The hot DuckDB window holds about a week; longer requests also read the Parquet history.
chart_bars <- function(mk, ticker, days) {
  rd <- function() candle_read(STORE, ticker, 60, 0, parquet_dir = if (days > 5) PARQUET)
  d <- rd(); st <- market_status(mk)
  if (!nrow(d) || (isTRUE(st$open) && epoch(Sys.time()) - max(d$bucket_start) > 300)) { live_state(mk); d <- rd() }
  cols <- c("ticker", "bucket", "open", "high", "low", "close", "volume")
  act <- CACHE[[mk]]$active; act <- if (NROW(act)) act[act$ticker == ticker, cols]
  x <- rbind(d[, cols], act)
  if (!nrow(x)) return(x)
  x <- x[order(x$bucket), ]; x <- x[!duplicated(x$bucket, fromLast = TRUE), ]
  dd <- local_day(x$bucket, mk)
  x[dd %in% head(sort(unique(dd), decreasing = TRUE), days), ]
}

# Daily Yahoo refresh of one market (cleaned like the research prices), cached 30 minutes
# and shared by the forecast and the daily chart bars. A failed fetch keeps the last good data.
daily_state <- function(mk, max_age = 1800) {
  key <- paste0("daily_", mk); c0 <- CACHE[[key]]
  if (!is.null(c0) && epoch(Sys.time()) - c0$at < max_age) return(c0$d)
  d <- tryCatch(FETCH_DAILY(names(QS$universe[[mk]]), mk), error = function(e) NULL)
  d <- if (!is.null(d) && !is.null(d$data)) tryCatch(clean_prices(d$data)$data, error = function(e) NULL)
  if (is.null(d) && !is.null(c0)) d <- c0$d
  CACHE[[key]] <- list(at = epoch(Sys.time()), d = d)
  d
}

forecast_state <- function(mk, max_age = 1800) {
  key <- paste0("fc_", mk); c0 <- CACHE[[key]]
  if (!is.null(c0) && epoch(Sys.time()) - c0$at < max_age) return(c0$f)
  m <- GHAR_LIVE[[mk]]; f <- NULL
  if (!is.null(m)) {
    d <- daily_state(mk, max_age)
    if (!is.null(d)) f <- tryCatch(ghar_live_forecast(d, m, mk), error = function(e) NULL)
  }
  CACHE[[key]] <- list(at = epoch(Sys.time()), f = f)
  f
}

# ---- chart workspace bars (/api/bars; docs/design/CHART_WORKSPACE.md) ----
SNAP <- snapshot_state()
check_ticker <- function(mk, ticker) {
  if (!ticker %in% names(QS$universe[[mk]])) bad_request(sprintf("unknown ticker for %s: %s", mk, ticker))
  ticker
}
store_last <- function(ticker, iv = 60)
  DBI::dbGetQuery(STORE, "SELECT max(bucket_start) b FROM candles WHERE ticker = ? AND interval_sec = ?",
                  params = list(ticker, as.integer(iv)))$b
act_rows <- function(mk, ticker) {
  a <- CACHE[[mk]]$active
  if (NROW(a)) a[a$ticker == ticker, c("bucket", "open", "high", "low", "close", "volume")] else NULL
}

# 1-minute store (+ forming bar) rolled up to w seconds, from `since` (epoch). Same freshness
# rule as chart_bars: fetch only on a cold store or when > 5 minutes behind during the session.
intraday_bars <- function(mk, ticker, w, since) {
  last <- store_last(ticker); st <- market_status(mk)
  if (is.na(last) || (isTRUE(st$open) && epoch(Sys.time()) - last > 300)) live_state(mk)
  act <- act_rows(mk, ticker)
  if (w == 60) {
    d <- candle_read(STORE, ticker, 60, since, parquet_dir = PARQUET)
    x <- rbind(d[, c("bucket", "open", "high", "low", "close", "volume")], act)
    if (!NROW(x)) return(empty_bars())
    x <- x[order(x$bucket), ]; return(x[!duplicated(x$bucket, fromLast = TRUE), ])
  }
  r <- if (is_duck(STORE)) rollup_intraday_duck(STORE, ticker, mk, w, since, PARQUET) else
    rollup_intraday_r(candle_read(STORE, ticker, 60, since), mk, w)
  if (!NROW(act)) return(r)
  a <- rollup_intraday_r(act, mk, w)                       # forming minute joins its bucket
  x <- rbind(r, a); x <- x[order(x$bucket), ]
  y <- agg_ohlc(x, as.numeric(x$bucket))
  data.frame(bucket = as.POSIXct(y$key, origin = "1970-01-01", tz = "UTC"), y[, -1])
}

# Research daily prices + the 30-minute daily refresh for newer dates + days the 1-minute store
# holds beyond that (today's forming session merged into the daily bar of the same date).
daily_bars <- function(mk, ticker) {
  cols <- c("date", "open", "high", "low", "close", "volume")
  h <- PRICES[PRICES$ticker == ticker, cols]
  r <- daily_state(mk); r <- if (!is.null(r)) r[r$ticker == ticker, cols]
  if (NROW(r)) h <- rbind(h, r[r$date > max(h$date, as.Date("1900-01-01")), ])
  m <- rbind(candle_read(STORE, ticker, 60, epoch(Sys.time()) - 10 * 86400)[, c("bucket", "open", "high", "low", "close", "volume")],
             act_rows(mk, ticker))
  if (NROW(m)) {
    m <- m[order(m$bucket), ]; m <- m[!duplicated(m$bucket, fromLast = TRUE), ]
    g <- agg_ohlc(m, local_day(m$bucket, mk)); g$date <- as.Date(g$key); g <- g[, cols]
    last <- if (nrow(h)) max(h$date) else as.Date("1900-01-01")
    today <- as.Date(format(Sys.time(), "%Y-%m-%d", tz = LIVE$sessions[[mk]]$tz))
    if (last == today && today %in% g$date) {            # the refresh's bar of today is up to 30 min old
      i <- which(h$date == today); j <- which(g$date == today)
      h$high[i] <- max(h$high[i], g$high[j]); h$low[i] <- min(h$low[i], g$low[j]); h$close[i] <- g$close[j]
      h$volume[i] <- max(h$volume[i], g$volume[j], na.rm = TRUE)
    }
    h <- rbind(h, g[g$date > last, ])
  }
  h[order(h$date), ]
}

bars_payload <- function(mk, ticker, interval, range, ind) {
  mk <- check_market(mk); check_ticker(mk, ticker)
  if (!interval %in% names(BAR_INTERVALS)) bad_request(paste("unknown interval:", interval))
  range <- toupper(range); if (!range %in% BAR_RANGES) bad_request(paste("unknown range:", range))
  specs <- parse_ind_spec(ind); w <- BAR_INTERVALS[[interval]]; st <- market_status(mk)
  tz <- LIVE$sessions[[mk]]$tz; notes <- character(); intraday <- w < 86400
  today <- as.Date(format(Sys.time(), "%Y-%m-%d", tz = tz))
  if (intraday) {
    if (w == 5) {
      sn <- snapshot_tick(SNAP, mk, ticker, STORE)
      notes <- c(notes, if (!sn$open) "market closed: 5s bars are built from live 2 s snapshots only during market hours"
                 else "snapshot-built: 5s bars from 2 s price snapshots (volume = change in cumulative volume)",
                 if (!is.null(sn$error)) paste("snapshot failed:", sn$error))
      x <- snapshot_bars(SNAP, ticker, STORE, epoch(Sys.time()) - 10 * 86400); source <- "snapshot_5s"
    } else {
      last <- store_last(ticker); last <- if (is.na(last)) epoch(Sys.time()) else last
      cut0 <- range_start(range, as.Date(format(as.POSIXct(last, origin = "1970-01-01", tz = "UTC"), "%Y-%m-%d", tz = tz)))
      since <- if (range == "ALL") 0 else if (range %in% c("1D", "5D")) last - (if (range == "1D") 10 else 14) * 86400 else
        as.numeric(as.POSIXct(format(cut0), tz = "UTC")) - 7 * 86400           # 7 days of warm-up for the indicators
      x <- intraday_bars(mk, ticker, w, since); source <- "store"
    }
    day <- local_day(x$bucket, mk)
    off <- as.POSIXlt(x$bucket, tz = tz)$gmtoff
    time <- epoch(x$bucket) + off; true_t <- epoch(x$bucket)
  } else {
    x <- daily_bars(mk, ticker)
    if (w > 86400) x <- rollup_daily(x, if (interval == "1w") "week" else "month")
    day <- x$date; time <- as.numeric(x$date) * 86400; source <- "daily"
    true_t <- as.numeric(as.POSIXct(paste(format(x$date), LIVE$sessions[[mk]]$open), tz = tz))   # session open of the bar's first day
  }
  start <- range_start(range, day)
  keep <- if (length(day)) day >= start else logical()
  if (length(day)) notes <- c(notes, range_note(range, day, start))
  vol <- ifelse(is.finite(x$volume), x$volume, 0)
  bd <- data.frame(time = time, open = x$open, high = x$high, low = x$low, close = x$close, volume = vol)
  ind_out <- compute_indicators(bd, specs, intraday, day, keep)
  notes <- c(notes, attr(ind_out, "notes")); attr(ind_out, "notes") <- NULL
  n <- sum(keep)
  list(market = mk, ticker = ticker, label = short(ticker), name = unname(QS$universe[[mk]][ticker]),
       interval = interval, range = range, tz = tz, source = source,
       live = isTRUE(st$open) && n > 0 && day[length(day)] == today,
       as_of = if (n) true_t[length(true_t)] else NA,
       note = if (length(notes)) paste(unique(notes), collapse = "; ") else NA,
       bars = bd[keep, , drop = FALSE], indicators = ind_out)
}

# /api/live payload (also read by the assistant)
live_payload <- function(mk) {
  s <- live_state(mk); st <- market_status(mk)
  base <- list(market = mk, open = st$open, local_time = st$local_time, updated_at = s$at,
               stale = isTRUE(s$stale), errors = as.list(s$errors))
  if (is.null(s$bars)) return(c(base, list(quotes = list())))
  cur <- pick_session(s$bars, mk); ch <- day_change(s$bars, s$meta, mk); rv <- intraday_rv(cur, mk)
  q <- do.call(rbind, lapply(split(cur, cur$ticker), function(x) {
    x <- x[order(x$bucket), ]; tk <- x$ticker[1]
    data.frame(ticker = tk, label = short(tk), name = unname(QS$universe[[mk]][tk]), last = tail(x$close, 1),
               change = unname(ch[tk]), rv = unname(rv[tk]), volume = sum(x$volume, na.rm = TRUE),
               last_time = epoch(tail(x$ts, 1)), feed = if (is.null(s$sources) || is.na(s$sources[tk])) "yahoo" else unname(s$sources[tk]))
  })); rownames(q) <- NULL
  spark <- lapply(split(cur, cur$ticker), function(x) round(tail(x$close[order(x$bucket)], 90), 4))
  n <- candle_stats(STORE, 60, PARQUET)
  c(base, list(newest_bar_age = epoch(Sys.time()) - max(epoch(s$bars$ts)), session_day = format(max(local_day(cur$bucket, mk))),
               fetch_sec = s$fetch_sec, range = s$range, quotes = q, spark = spark,
               store = list(candles = n$n, tickers = n$t, written = s$store[["written"]], rejected = s$store[["rejected"]])))
}

graph_payload <- function(g, P, extra = NULL) {
  idx <- which(g$adj == 1 & upper.tri(g$adj), arr.ind = TRUE)
  list(nodes = c(list(id = g$tick, label = short(g$tick)), extra),
       edges = list(source = g$tick[idx[, 1]], target = g$tick[idx[, 2]], rho = round(g$rho[idx], 4)),
       P = round(unname(P), 5))
}

#* @apiTitle Q-Stock API
#* @apiDescription Live market data, quantum-walk graph analytics and research results (all computed in R).

#* Exchange sessions and universes
#* @get /api/status
#* @serializer unboxedJSON list(na = "null", digits = NA)
function() {
  lapply(names(QS$universe), function(mk) {
    st <- market_status(mk)
    list(market = mk, open = st$open, local_time = st$local_time, tz = LIVE$sessions[[mk]]$tz,
         tickers = data.frame(ticker = names(QS$universe[[mk]]), label = short(names(QS$universe[[mk]])),
                              name = unname(QS$universe[[mk]])))
  })
}

#* Live quotes for one market (shared one-minute cache)
#* @param market NSE or NASDAQ
#* @get /api/live/<market>
#* @serializer unboxedJSON list(na = "null", digits = NA)
function(market) live_payload(check_market(market))

#* One-minute candles of the latest session(s) from the candle store (time shifted to exchange-local clock time)
#* @param market NSE or NASDAQ
#* @param ticker Yahoo symbol
#* @param days number of latest sessions, 1 to 30 (default 1)
#* @get /api/candles/<market>/<ticker>
#* @serializer unboxedJSON list(na = "null", digits = NA)
function(market, ticker, days = 1) {
  mk <- check_market(market); days <- suppressWarnings(as.integer(days))
  days <- if (is.na(days)) 1L else min(max(days, 1L), 30L)
  x <- chart_bars(mk, ticker, days)
  if (!nrow(x)) return(list(ticker = ticker, candles = list()))
  off <- as.POSIXlt(x$bucket, tz = LIVE$sessions[[mk]]$tz)$gmtoff
  vol <- ifelse(is.finite(x$volume), x$volume, 0); day <- local_day(x$bucket, mk)
  cv <- ave(vol, day, FUN = cumsum); cpv <- ave((x$high + x$low + x$close) / 3 * vol, day, FUN = cumsum)   # VWAP resets each session
  list(ticker = ticker, label = short(ticker), active_last = isTRUE(CACHE[[mk]]$n_active > 0),
       candles = data.frame(time = epoch(x$bucket) + off, open = x$open, high = x$high, low = x$low, close = x$close,
                            volume = vol, vwap = ifelse(cv > 0, cpv / cv, NA)))
}

#* Chart bars of one stock at any interval and range, with indicators computed in R (docs/design/CHART_WORKSPACE.md §3)
#* @param market NSE or NASDAQ
#* @param ticker Yahoo symbol of the market's universe
#* @param interval 5s, 1m, 5m, 15m, 30m, 1h, 1d, 1w or 1mo (default 1m)
#* @param range 1D, 5D, 1M, 3M, 6M, YTD, 1Y, 5Y or ALL (default 1D)
#* @param ind comma list of at most 8: vwap, sma:n, ema:n, bb:n:k, rsi:n (n 2..500, k 0.5..5)
#* @get /api/bars/<market>/<ticker>
#* @serializer unboxedJSON list(na = "null", digits = NA)
function(market, ticker, interval = "1m", range = "1D", ind = "") bars_payload(market, ticker, interval, range, ind)

#* Live correlation graph of one-minute returns with QSW node features
#* @param market NSE or NASDAQ
#* @param omega QSW dial, 0 (quantum) to 1 (classical)
#* @param look number of one-minute returns
#* @get /api/graph/<market>
#* @serializer unboxedJSON list(na = "null", digits = NA)
function(market, omega = 0.25, look = 120) {
  mk <- check_market(market); s <- live_state(mk)
  omega <- min(max(as.numeric(omega), 0), 1); look <- min(max(as.integer(look), 30), 375)
  if (is.null(s$bars)) return(list(nodes = NULL))
  key <- sprintf("%d_%.2f", look, omega)
  if (!is.null(s$walks[[key]])) return(s$walks[[key]])
  g <- live_graph(intraday_returns_wide(pick_session(s$bars, mk, min_bars = 31), last_n = look))
  if (is.null(g)) return(list(nodes = NULL))
  cur <- pick_session(s$bars, mk); rv <- intraday_rv(cur, mk); ch <- day_change(s$bars, s$meta, mk)
  w <- live_walk(g, omega, rv)
  out <- c(list(market = mk, omega = omega, n_bars = g$n_bars),
           graph_payload(g, attr(w, "P"), list(change = unname(ch[g$tick]), rv = unname(rv[g$tick]),
                                                q_self = w$q_self, q_ent = w$q_ent, q_volspill = w$q_volspill)))
  s$walks[[key]] <- out
  out
}

#* Graph-HAR 5-day volatility forecast from completed sessions (30-minute cache)
#* @param market NSE or NASDAQ
#* @get /api/forecast/<market>
#* @serializer unboxedJSON list(na = "null", digits = NA)
function(market) {
  mk <- check_market(market); f <- forecast_state(mk); m <- GHAR_LIVE[[mk]]
  list(market = mk, available = !is.null(f), forecasts = f,
       model = if (is.null(m)) NULL else list(train_from = format(m$train_from), train_to = format(m$train_to), n = m$n))
}

#* Historical quantum dial: QSW on the daily 60-day correlation graph of one date
#* @param market NSE or NASDAQ
#* @param date YYYY-MM-DD (default: latest)
#* @param omega QSW dial
#* @get /api/dial
#* @serializer unboxedJSON list(na = "null", digits = NA)
function(market = "NASDAQ", date = "", omega = 0.25) {
  mk <- check_market(market); R <- RW[[mk]]; dts <- as.Date(rownames(R))
  d <- if (nzchar(date)) as.Date(date) else max(dts); t <- max(which(dts <= d))
  win <- R[(t - QS$corr_window + 1):t, , drop = FALSE]
  ok <- colMeans(!is.na(win)) >= 0.8 & !is.na(R[t, ])
  rho <- suppressWarnings(cor(win[, ok], use = "pairwise.complete.obs"))
  g <- c(knn_graph(rho, QS$knn_k), list(tick = colnames(R)[ok], rho = rho))
  omega <- min(max(as.numeric(omega), 0), 1)
  key <- sprintf("dial_%s_%s_%.2f", mk, format(dts[t]), omega)
  if (!is.null(CACHE[[key]])) return(CACHE[[key]])
  # Precomputed by the same R code (scripts/25_export_snapshot.R) for the latest date: served as is.
  pre <- file.path(ROOT, "api", "precomputed", sprintf("dial_%s_%03d.json", mk, round(omega * 100)))
  if (file.exists(pre)) {
    j <- jsonlite::fromJSON(pre, simplifyVector = FALSE)
    if (identical(j$date, format(dts[t]))) { CACHE[[key]] <- j; return(j) }
  }
  lim <- paste0("lim_", mk, "_", format(dts[t]))           # the two limits never change for a date
  Pn <- function(om) { P <- pmax(qsw_distributions(g$w, om, TAUS, exact_limits = TRUE), 0); round(unname(P / rowSums(P)), 5) }
  if (is.null(CACHE[[lim]])) CACHE[[lim]] <- list(q = Pn(0), c = Pn(1))
  out <- c(list(market = mk, date = format(dts[t]), omega = omega, min_date = format(dts[QS$corr_window + 1]), max_date = format(max(dts))),
           graph_payload(g, Pn(omega)), list(P_quantum = CACHE[[lim]]$q, P_classical = CACHE[[lim]]$c))
  CACHE[[key]] <- out
  out
}

#* Compute-speed check of this host (one 20-node QSW walk at omega = 0.25 and at the exact limits)
#* @get /api/bench
#* @serializer unboxedJSON list(na = "null", digits = NA)
function() {
  set.seed(1); r <- matrix(runif(400), 20); W <- knn_graph((r + t(r)) / 2, 4)$w
  tm <- function(expr) as.numeric(system.time(expr)[["elapsed"]])
  list(qsw_rk4_omega_025 = tm(qsw_distributions(W, 0.25, TAUS)),
       qsw_exact_omega_0 = tm(qsw_distributions(W, 0, TAUS, exact_limits = TRUE)),
       qsw_exact_omega_1 = tm(qsw_distributions(W, 1, TAUS, exact_limits = TRUE)),
       r_loop_1e6 = tm({ s <- 0; for (i in 1:1e6) s <- s + i }), cores = parallel::detectCores())
}

#* Research results for the UI (read from results/tables; nothing is recomputed)
#* @get /api/results
#* @serializer unboxedJSON list(na = "null", digits = NA)
function() {
  h <- tab("v2_hypothesis_tests.csv")
  dial <- if (!is.null(h)) {
    x <- h[h$hypothesis == "H2" & h$target == "T1", c("market", "loss", "model_a", "mean_diff_a_minus_b", "ci_lo", "ci_hi", "p_holm")]
    x$omega <- as.numeric(sub("qsw_w", "", x$model_a)) / 100; x$model_a <- NULL; names(x)[3] <- "diff"; x
  }
  mlp <- tab("v3_mlp_vs_linear.csv"); if (!is.null(mlp)) mlp <- mlp[startsWith(mlp$model, "MLP"), ]
  list(dial_curve = dial, tuned = tab("v3_tuned_models.csv"), tuned_tests = tab("v3_tuned_models_tests.csv"),
       lightgbm = tab("v3_lightgbm.csv"), ghar_pairwise = tab("v2_ghar_pairwise.csv"), naive = tab("naive_baseline.csv"),
       power = tab("power_analysis_summary.csv"), gpu = tab("gpu_benchmark.csv"), spark = tab("spark_scaling.csv"),
       robustness = tab("v2_robustness_tickers.csv"), economic = tab("v2_economic_value.csv"),
       mlp = mlp, mlp_status = if (is.null(mlp)) "pending" else "final",
       mr_groups = { m <- tab("mr_monthly_stats.csv"); if (is.null(m)) NA else nrow(m) })
}

# ---- explainable forecast, news, sign-in and the assistant ----

explain_state <- function(mk, ticker) {
  f <- forecast_state(mk); m <- GHAR_LIVE[[mk]]
  if (is.null(f) || is.null(m)) return(NULL)
  explain_forecast(f, m$coef, ticker)
}

news_state <- function(mk, ticker, max_age = 600) {
  key <- paste0("news_", ticker); c0 <- CACHE[[key]]
  if (!is.null(c0) && epoch(Sys.time()) - c0$at < max_age) return(c0$n)
  n <- tryCatch(FETCH_NEWS(ticker, unname(QS$universe[[mk]][ticker])), error = function(e) list(items = news_empty(), errors = c(all = conditionMessage(e))))
  n$items <- news_clean(n$items)
  if (!nrow(n$items) && !is.null(c0) && nrow(c0$n$items)) { c0$n$errors <- n$errors; c0$n$stale <- TRUE; return(c0$n) }
  n$stale <- FALSE; n$fetched_at <- epoch(Sys.time())
  CACHE[[key]] <- list(at = epoch(Sys.time()), n = n)
  n
}

json_body <- function(req) {
  b <- tryCatch(jsonlite::fromJSON(req$postBody %||% "", simplifyVector = TRUE), error = function(e) NULL)
  if (!is.list(b)) bad_request("request body must be a JSON object")
  b
}
need_user <- function(req, res) {
  if (!auth_enabled(AUTH_STORE)) return(list(username = "local", display_name = "Local user", role = "analyst"))
  u <- auth_user(AUTH_STORE, auth_token_of(req))
  if (is.null(u)) { res$status <- 401; return(NULL) }
  u
}

#* Explainable volatility forecast: exact per-feature decomposition of one stock's graph-HAR forecast
#* @param market NSE or NASDAQ
#* @param ticker Yahoo symbol
#* @get /api/explain/<market>/<ticker>
#* @serializer unboxedJSON list(na = "null", digits = NA)
function(market, ticker) {
  mk <- check_market(market); check_ticker(mk, ticker)
  e <- explain_state(mk, ticker)
  m <- GHAR_LIVE[[mk]]
  rs <- tab("explainability_shap.csv")
  list(market = mk, ticker = ticker, label = short(ticker), name = unname(QS$universe[[mk]][ticker]),
       available = !is.null(e), explanation = e,
       model = if (is.null(m)) NULL else list(train_from = format(m$train_from), train_to = format(m$train_to), n = m$n,
                                              coef = as.list(stats::setNames(as.numeric(m$coef), c("intercept", GHAR_COLS)))),
       research_shap = if (is.null(rs)) NULL else rs[rs$market == mk & rs$task == "T1_volatility", ])
}

#* Latest news headlines of one stock (Yahoo Finance; GDELT when Yahoo returns nothing; 10-minute cache)
#* @param market NSE or NASDAQ
#* @param ticker Yahoo symbol
#* @get /api/news/<market>/<ticker>
#* @serializer unboxedJSON list(na = "null", digits = NA)
function(market, ticker) {
  mk <- check_market(market); check_ticker(mk, ticker)
  n <- news_state(mk, ticker)
  list(market = mk, ticker = ticker, label = short(ticker), fetched_at = n$fetched_at %||% NA, stale = isTRUE(n$stale),
       errors = as.list(n$errors), items = n$items)
}

#* Data feeds in use (live prices and news)
#* @get /api/feeds
#* @serializer unboxedJSON list(na = "null", digits = NA)
function() {
  list(prices = list(NSE = if (identical(KOTAK_LOGIN, "connected")) "kotak_neo (Yahoo fallback)" else "yahoo", NASDAQ = "yahoo"),
       kotak_neo = KOTAK_LOGIN, news = "yahoo (GDELT fallback)", research = "daily Yahoo prices frozen at QS$end_date")
}

#* Whether sign-in is enabled on this server
#* @get /api/auth/config
#* @serializer unboxedJSON
function() list(enabled = auth_enabled(AUTH_STORE), session_hours = AUTH$session_hours)

#* Sign in; body {"username": "...", "password": "..."}; returns a bearer token
#* @post /api/auth/login
#* @serializer unboxedJSON
function(req, res) {
  b <- json_body(req)
  if (!auth_enabled(AUTH_STORE)) { res$status <- 404; return(list(error = "sign-in is not enabled on this server")) }
  r <- auth_login(AUTH_STORE, b$username, b$password)
  if (!r$ok) { res$status <- r$status; return(list(error = r$error)) }
  r[c("token", "expires_at", "user")]
}

#* The signed-in user
#* @get /api/auth/me
#* @serializer unboxedJSON
function(req, res) {
  u <- auth_user(AUTH_STORE, auth_token_of(req))
  if (is.null(u)) { res$status <- 401; return(list(error = "not signed in")) }
  u
}

#* Sign out (ends the session token)
#* @post /api/auth/logout
#* @serializer unboxedJSON
function(req) { auth_logout(AUTH_STORE, auth_token_of(req)); list(ok = TRUE) }

#* Ask the Q-Stock assistant (signed-in users); body {"message": "...", "market": "NSE"}
#* @post /api/chat
#* @serializer unboxedJSON list(na = "null", digits = NA)
function(req, res) {
  u <- need_user(req, res); if (is.null(u)) return(list(error = "sign in to use the assistant"))
  b <- json_body(req)
  hint <- if (identical(b$market, "NASDAQ")) "NASDAQ" else "NSE"
  ctx <- list(live = live_payload,
              forecast = forecast_state, explain = explain_state, news = news_state, table = tab)
  r <- assistant_reply(b$message, ctx, hint)
  c(r, list(user = u$display_name, at = epoch(Sys.time())))
}

#* @plumber
function(pr) {
  # Server-Timing header: compute time of every request (visible in browser dev tools / curl -I).
  pr <- plumber::pr_hooks(pr, list(
    exit = function() candle_store_close(STORE),         # DuckDB: checkpoint and release the file lock
    preroute = function(req) req$qs_t0 <- Sys.time(),
    postroute = function(req, res) {
      if (!is.null(req$qs_t0))
        res$setHeader("Server-Timing", sprintf("r;dur=%.0f", 1000 * as.numeric(difftime(Sys.time(), req$qs_t0, units = "secs"))))
      # Hashed build assets never change; the HTML page must always be revalidated.
      p <- req$PATH_INFO
      if (startsWith(p, "/assets/")) res$setHeader("Cache-Control", "public, max-age=31536000, immutable")
      else if (p %in% c("/", "/index.html")) res$setHeader("Cache-Control", "no-cache")
    }))
  pr <- plumber::pr_set_error(pr, function(req, res, err) {
    res$status <- if (inherits(err, "qs_bad_request")) 400 else 500
    list(error = conditionMessage(err))
  })
  # GET API plus sign-in/chat POSTs (bearer tokens, no cookies): allow a UI hosted elsewhere (e.g. Vercel, VITE_API_URL) to call it.
  pr <- plumber::pr_filter(pr, "cors", function(req, res) {
    res$setHeader("Access-Control-Allow-Origin", "*")
    res$setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    res$setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization")
    if (identical(req$REQUEST_METHOD, "OPTIONS")) { res$status <- 204; return(list()) }
    plumber::forward()
  })
  dist <- file.path(ROOT, "web", "dist")
  if (dir.exists(dist)) {
    # plumber's static handler hangs on directory paths (e.g. /assets/); answer those with 404.
    pr <- plumber::pr_filter(pr, "no_dirs", function(req, res) {
      path <- req$PATH_INFO
      if (path != "/" && !startsWith(path, "/api/") && dir.exists(file.path(dist, path))) {
        res$status <- 404
        return(list(error = "not found"))
      }
      plumber::forward()
    })
    pr <- plumber::pr_static(pr, "/", dist)
  }
  pr
}
