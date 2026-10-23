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
FETCH <- getOption("qstock.live_fetcher", fetch_intraday_many)
FETCH_DAILY <- getOption("qstock.live_daily_fetcher", fetch_daily_many)
STORE <- candle_store_open(getOption("qstock.live_db", file.path(ROOT, LIVE$db_path)))
CACHE <- new.env()
TAUS <- QS$walk_time * seq_len(10) / 10
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
  out <- list(at = epoch(Sys.time()), bars = rbind(s$final, s$active), n_active = nrow(s$active),
              meta = lapply(r$data, attr, "meta"), errors = r$errors, stale = FALSE, range = rng,
              fetch_sec = as.numeric(difftime(Sys.time(), t0, units = "secs")),
              store = candle_upsert(STORE, s$final, 60, "yahoo_poll"), walks = new.env())
  CACHE[[mk]] <- out
  out
}

forecast_state <- function(mk, max_age = 1800) {
  key <- paste0("fc_", mk); c0 <- CACHE[[key]]
  if (!is.null(c0) && epoch(Sys.time()) - c0$at < max_age) return(c0$f)
  m <- GHAR_LIVE[[mk]]; f <- NULL
  if (!is.null(m)) {
    d <- tryCatch(FETCH_DAILY(names(QS$universe[[mk]]), mk), error = function(e) NULL)
    if (!is.null(d) && !is.null(d$data))
      f <- tryCatch(ghar_live_forecast(clean_prices(d$data)$data, m, mk), error = function(e) NULL)
  }
  CACHE[[key]] <- list(at = epoch(Sys.time()), f = f)
  f
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
function(market) {
  mk <- check_market(market); s <- live_state(mk); st <- market_status(mk)
  base <- list(market = mk, open = st$open, local_time = st$local_time, updated_at = s$at,
               stale = isTRUE(s$stale), errors = as.list(s$errors))
  if (is.null(s$bars)) return(c(base, list(quotes = list())))
  cur <- pick_session(s$bars, mk); ch <- day_change(s$bars, s$meta, mk); rv <- intraday_rv(cur, mk)
  q <- do.call(rbind, lapply(split(cur, cur$ticker), function(x) {
    x <- x[order(x$bucket), ]; tk <- x$ticker[1]
    data.frame(ticker = tk, label = short(tk), name = unname(QS$universe[[mk]][tk]), last = tail(x$close, 1),
               change = unname(ch[tk]), rv = unname(rv[tk]), volume = sum(x$volume, na.rm = TRUE),
               last_time = epoch(tail(x$ts, 1)))
  })); rownames(q) <- NULL
  spark <- lapply(split(cur, cur$ticker), function(x) round(tail(x$close[order(x$bucket)], 90), 4))
  n <- DBI::dbGetQuery(STORE, "SELECT COUNT(*) n, COUNT(DISTINCT ticker) t FROM candles WHERE interval_sec = 60")
  c(base, list(newest_bar_age = epoch(Sys.time()) - max(epoch(s$bars$ts)), session_day = format(max(local_day(cur$bucket, mk))),
               fetch_sec = s$fetch_sec, range = s$range, quotes = q, spark = spark,
               store = list(candles = n$n, tickers = n$t, written = s$store[["written"]], rejected = s$store[["rejected"]])))
}

#* One-minute candles of the latest session (time shifted to exchange-local clock time)
#* @param market NSE or NASDAQ
#* @param ticker Yahoo symbol
#* @get /api/candles/<market>/<ticker>
#* @serializer unboxedJSON list(na = "null", digits = NA)
function(market, ticker) {
  mk <- check_market(market); s <- live_state(mk)
  if (is.null(s$bars)) return(list(ticker = ticker, candles = list()))
  x <- pick_session(s$bars, mk); x <- x[x$ticker == ticker, ]; x <- x[order(x$bucket), ]
  off <- as.POSIXlt(x$bucket, tz = LIVE$sessions[[mk]]$tz)$gmtoff
  vol <- ifelse(is.finite(x$volume), x$volume, 0); cv <- cumsum(vol)
  list(ticker = ticker, label = short(ticker), active_last = isTRUE(s$n_active > 0),
       candles = data.frame(time = epoch(x$bucket) + off, open = x$open, high = x$high, low = x$low, close = x$close,
                            volume = vol, vwap = ifelse(cv > 0, cumsum((x$high + x$low + x$close) / 3 * vol) / cv, NA)))
}

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

#* @plumber
function(pr) {
  # Server-Timing header: compute time of every request (visible in browser dev tools / curl -I).
  pr <- plumber::pr_hooks(pr, list(
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
  # Read-only GET API: allow a UI hosted elsewhere (e.g. Vercel, VITE_API_URL) to call it.
  pr <- plumber::pr_filter(pr, "cors", function(req, res) {
    res$setHeader("Access-Control-Allow-Origin", "*")
    res$setHeader("Access-Control-Allow-Methods", "GET, OPTIONS")
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
