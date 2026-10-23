# Live market module: near-real-time intraday candles, a hot/cold candle store,
# an event-time tick aggregator, and live graph analytics for the dashboard.
#
# Source: Yahoo chart API, polled (free, unofficial; NSE bars arrive within seconds,
# but there is no service-level guarantee). Live data are for viewing only and never
# enter the research datasets or results.
#
# Storage design (same idea as a Redis + PostgreSQL pipeline, without servers):
#   hot  = the active (still-forming) candle of each ticker, kept in memory
#   cold = finalised candles in SQLite via DBI, written with an idempotent upsert
#          keyed by (ticker, interval_sec, bucket_start). The SQL is also valid
#          PostgreSQL (>= 9.5), so RPostgres can replace RSQLite by changing the
#          connection only.

LIVE <- list(
  sessions = list(NSE = list(tz = "Asia/Kolkata", open = "09:15", close = "15:30", bars_per_day = 375),
                  NASDAQ = list(tz = "America/New_York", open = "09:30", close = "16:00", bars_per_day = 390)),
  db_path = file.path("data", "live", "candles.sqlite"),
  grace_sec = 5,          # watermark delay for late ticks / still-forming bars
  retention_sec = 3600    # finalised candles kept in memory for late corrections
)

# ---- exchange sessions ----

# Weekday and exchange-hours check in the exchange's own time zone (DST-aware).
# Exchange holidays are not modelled; the dashboard flags them as "open by clock,
# no recent bars" instead.
market_status <- function(market, now = Sys.time()) {
  s <- LIVE$sessions[[market]]
  loc <- as.POSIXlt(now, tz = s$tz)
  day <- format(loc, "%Y-%m-%d")
  o <- as.POSIXct(paste(day, s$open), tz = s$tz)
  cl <- as.POSIXct(paste(day, s$close), tz = s$tz)
  open <- loc$wday %in% 1:5 && as.numeric(now) >= as.numeric(o) && as.numeric(now) < as.numeric(cl)
  list(open = open, local_time = format(loc, "%a %H:%M %Z"), session_open = o, session_close = cl,
       minutes_open = if (open) as.numeric(difftime(now, o, units = "mins")) else NA_real_)
}

# ---- Yahoo chart API ----

yahoo_chart_url <- function(symbol, interval = "1m", range = "1d") {
  sprintf("https://query1.finance.yahoo.com/v8/finance/chart/%s?interval=%s&range=%s&includePrePost=false",
          utils::URLencode(symbol, reserved = TRUE), interval, range)
}

# Intraday bars from one chart-API response. The last bar of an open session is the
# still-forming one; its timestamp is the latest trade, not a bucket boundary.
parse_intraday <- function(json_text, symbol) {
  j <- jsonlite::fromJSON(json_text, simplifyVector = FALSE)
  res <- j$chart$result[[1]]
  if (is.null(res) || is.null(res$timestamp)) return(NULL)
  q <- res$indicators$quote[[1]]
  num <- function(x) vapply(x, function(v) if (is.null(v)) NA_real_ else as.numeric(v), 0)
  d <- data.frame(ticker = symbol,
                  ts = as.POSIXct(unlist(res$timestamp), origin = "1970-01-01", tz = "UTC"),
                  open = num(q$open), high = num(q$high), low = num(q$low), close = num(q$close),
                  volume = num(q$volume))
  d <- d[is.finite(d$close) & is.finite(d$open) & is.finite(d$high) & is.finite(d$low), ]
  m <- res$meta
  attr(d, "meta") <- list(prev_close = m$chartPreviousClose %||% NA_real_,
                          price = m$regularMarketPrice %||% NA_real_,
                          market_time = as.POSIXct(m$regularMarketTime %||% NA_real_, origin = "1970-01-01", tz = "UTC"))
  d
}

# Fetch many symbols concurrently (curl multi). Returns parsed results and per-symbol errors;
# one failed symbol never stops the others.
fetch_many <- function(symbols, url_fun, parse_fun, timeout = 20) {
  out <- list(); errs <- character()
  pool <- curl::new_pool(host_con = 6)
  for (s in symbols) local({
    sym <- s
    h <- curl::new_handle(useragent = "Mozilla/5.0", timeout = timeout)
    curl::curl_fetch_multi(url_fun(sym), handle = h, pool = pool,
      done = function(r) {
        if (r$status_code != 200) { errs[[sym]] <<- paste("HTTP", r$status_code); return() }
        d <- tryCatch(parse_fun(rawToChar(r$content), sym), error = function(e) NULL)
        if (is.null(d) || !nrow(d)) errs[[sym]] <<- "no data" else out[[sym]] <<- d
      },
      fail = function(msg) errs[[sym]] <<- msg)
  })
  curl::multi_run(pool = pool)
  list(data = out, errors = errs)
}

fetch_intraday_many <- function(symbols, interval = "1m", range = "1d")
  fetch_many(symbols, function(s) yahoo_chart_url(s, interval, range), parse_intraday)

fetch_daily_many <- function(symbols, market, range = "1y") {
  r <- fetch_many(symbols, function(s) yahoo_chart_url(s, "1d", range), function(txt, s) parse_yahoo_daily(txt, s, market))
  r$data <- if (length(r$data)) do.call(rbind, r$data) else NULL
  r
}

# ---- bars -> buckets, hot/cold split ----

bucket_of <- function(ts, interval_sec)
  as.POSIXct(floor(as.numeric(ts) / interval_sec) * interval_sec, origin = "1970-01-01", tz = "UTC")

# Assign bars to buckets (one row per ticker x bucket, keeping the most recent bar of a
# bucket) and split them into finalised bars and the active (still-forming) ones.
split_active <- function(bars, interval_sec = 60, now = Sys.time(), market_open = TRUE) {
  bars$bucket <- bucket_of(bars$ts, interval_sec)
  bars <- bars[order(bars$ticker, bars$bucket, bars$ts), ]
  bars <- bars[!duplicated(bars[, c("ticker", "bucket")], fromLast = TRUE), ]
  active <- market_open & as.numeric(bars$bucket) + interval_sec + LIVE$grace_sec > as.numeric(now)
  list(final = bars[!active, ], active = bars[active, ])
}

# ---- cold store (SQLite via DBI; the SQL is PostgreSQL-compatible) ----

CANDLE_DDL <- "CREATE TABLE IF NOT EXISTS candles (
  ticker        TEXT    NOT NULL,
  interval_sec  INTEGER NOT NULL,
  bucket_start  BIGINT  NOT NULL,   -- epoch seconds, UTC, start of the bucket
  open          DOUBLE PRECISION NOT NULL,
  high          DOUBLE PRECISION NOT NULL,
  low           DOUBLE PRECISION NOT NULL,
  close         DOUBLE PRECISION NOT NULL,
  volume        DOUBLE PRECISION,
  source        TEXT    NOT NULL,
  updated_at    BIGINT  NOT NULL,
  PRIMARY KEY (ticker, interval_sec, bucket_start),
  CHECK (high >= low AND high >= open AND high >= close AND low <= open AND low <= close)
)"

candle_store_open <- function(path = LIVE$db_path) {
  if (path != ":memory:") dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  DBI::dbExecute(con, CANDLE_DDL)
  con
}

# Idempotent upsert: writing the same candle twice leaves one row, and a revised candle
# (late correction) replaces the stored values. Bars violating OHLC consistency are
# rejected and counted, never stored.
candle_upsert <- function(con, candles, interval_sec, source) {
  if (is.null(candles) || !nrow(candles)) return(c(written = 0L, rejected = 0L))
  ok <- with(candles, is.finite(open) & is.finite(close) & high >= pmax(open, close, low) & low <= pmin(open, close))
  if (!any(ok)) return(c(written = 0L, rejected = sum(!ok)))
  df <- with(candles[ok, ], data.frame(ticker = ticker, interval_sec = as.integer(interval_sec),
             bucket_start = as.numeric(bucket), open = open, high = high, low = low, close = close,
             volume = volume, source = source, updated_at = as.numeric(Sys.time())))
  if (nrow(df)) DBI::dbWithTransaction(con, DBI::dbExecute(con,
    "INSERT INTO candles VALUES (:ticker, :interval_sec, :bucket_start, :open, :high, :low, :close, :volume, :source, :updated_at)
     ON CONFLICT (ticker, interval_sec, bucket_start) DO UPDATE SET
       open = excluded.open, high = excluded.high, low = excluded.low, close = excluded.close,
       volume = excluded.volume, source = excluded.source, updated_at = excluded.updated_at",
    params = as.list(df)))
  c(written = nrow(df), rejected = sum(!ok))
}

candle_read <- function(con, ticker, interval_sec = 60, since = 0) {
  d <- DBI::dbGetQuery(con, "SELECT * FROM candles WHERE ticker = ? AND interval_sec = ? AND bucket_start >= ?
                             ORDER BY bucket_start", params = list(ticker, as.integer(interval_sec), as.numeric(since)))
  d$bucket <- as.POSIXct(d$bucket_start, origin = "1970-01-01", tz = "UTC")
  d
}

# ---- event-time tick aggregator (for a WebSocket tick feed) ----
# Ticks: data.frame(ticker, ts [POSIXct], price, size, id [optional]).
# * Buckets by event time (exchange timestamp), not arrival time.
# * Watermark = latest event time seen - grace; a bucket is finalised once its end is
#   at or before the watermark, so slightly late, out-of-order ticks still land correctly.
# * Duplicate tick ids are dropped (replays / reconnects).
# * A tick for an already finalised bucket produces a corrected candle (to be upserted);
#   beyond the retention window it is counted as too late and dropped.
# No free tick feed is available, so this path is validated on synthetic and replayed
# ticks (tests); the live dashboard uses polled bars.
tick_aggregator <- function(interval_sec = 60, grace_sec = LIVE$grace_sec, retention_sec = LIVE$retention_sec) {
  e <- new.env()
  e$interval <- interval_sec; e$grace <- grace_sec; e$retention <- retention_sec
  e$active <- new.env(hash = TRUE); e$final <- new.env(hash = TRUE); e$seen <- new.env(hash = TRUE)
  e$max_event <- -Inf; e$stats <- c(ticks = 0, duplicates = 0, late_corrections = 0, too_late = 0)
  e
}

.merge_tick <- function(cd, t, p, v) {
  if (is.null(cd)) return(list(first = t, last = t, open = p, high = p, low = p, close = p, volume = v))
  if (t < cd$first) { cd$first <- t; cd$open <- p }
  if (t >= cd$last) { cd$last <- t; cd$close <- p }
  cd$high <- max(cd$high, p); cd$low <- min(cd$low, p); cd$volume <- cd$volume + v
  cd
}

.candles_df <- function(keys, env) {
  if (!length(keys)) return(data.frame(ticker = character(), bucket = as.POSIXct(character(), tz = "UTC"),
                                       open = numeric(), high = numeric(), low = numeric(), close = numeric(), volume = numeric()))
  parts <- strsplit(keys, "|", fixed = TRUE)
  cs <- mget(keys, envir = env)
  data.frame(ticker = vapply(parts, `[`, "", 1),
             bucket = as.POSIXct(as.numeric(vapply(parts, `[`, "", 2)), origin = "1970-01-01", tz = "UTC"),
             open = vapply(cs, `[[`, 0, "open"), high = vapply(cs, `[[`, 0, "high"), low = vapply(cs, `[[`, 0, "low"),
             close = vapply(cs, `[[`, 0, "close"), volume = vapply(cs, `[[`, 0, "volume"), row.names = NULL)
}

agg_push <- function(agg, ticks) {
  ts <- as.numeric(ticks$ts); ids <- if (is.null(ticks$id)) rep(NA_character_, nrow(ticks)) else as.character(ticks$id)
  corrected <- character()
  for (i in seq_len(nrow(ticks))) {
    agg$stats[["ticks"]] <- agg$stats[["ticks"]] + 1
    if (!is.na(ids[i])) {
      if (exists(ids[i], envir = agg$seen, inherits = FALSE)) { agg$stats[["duplicates"]] <- agg$stats[["duplicates"]] + 1; next }
      assign(ids[i], TRUE, envir = agg$seen)
    }
    b <- floor(ts[i] / agg$interval) * agg$interval
    key <- paste(ticks$ticker[i], b, sep = "|")
    if (exists(key, envir = agg$final, inherits = FALSE)) {
      assign(key, .merge_tick(get(key, envir = agg$final), ts[i], ticks$price[i], ticks$size[i]), envir = agg$final)
      agg$stats[["late_corrections"]] <- agg$stats[["late_corrections"]] + 1
      corrected <- union(corrected, key)
    } else if (b + agg$interval <= agg$max_event - agg$grace - agg$retention) {
      agg$stats[["too_late"]] <- agg$stats[["too_late"]] + 1
    } else {
      cur <- if (exists(key, envir = agg$active, inherits = FALSE)) get(key, envir = agg$active) else NULL
      assign(key, .merge_tick(cur, ts[i], ticks$price[i], ticks$size[i]), envir = agg$active)
    }
    agg$max_event <- max(agg$max_event, ts[i])
  }
  corrected <- .candles_df(sort(corrected), agg$final)   # read before pruning
  list(finalized = agg_advance(agg), corrected = corrected)
}

# Move active buckets whose end is at or before the watermark to the finalised set and
# prune finalised buckets older than the retention window. Returns the newly finalised candles.
agg_advance <- function(agg, watermark = agg$max_event - agg$grace) {
  keys <- ls(agg$active)
  b <- as.numeric(vapply(strsplit(keys, "|", fixed = TRUE), `[`, "", 2))
  done <- sort(keys[b + agg$interval <= watermark])
  for (k in done) { assign(k, get(k, envir = agg$active), envir = agg$final); rm(list = k, envir = agg$active) }
  out <- .candles_df(done, agg$final)
  fk <- ls(agg$final)
  if (is.finite(watermark) && length(fk)) {
    fb <- as.numeric(vapply(strsplit(fk, "|", fixed = TRUE), `[`, "", 2))
    old <- fk[fb + agg$interval <= watermark - agg$retention]
    if (length(old)) rm(list = old, envir = agg$final)
  }
  out
}

agg_active <- function(agg) .candles_df(ls(agg$active), agg$active)

# Finalise everything (end of session or shutdown).
agg_flush <- function(agg) agg_advance(agg, Inf)

# Expand 1-minute bars into an ordered tick path open -> low/high -> close (for replay tests).
bars_to_ticks <- function(bars) {
  do.call(rbind, lapply(seq_len(nrow(bars)), function(i) {
    b <- bars[i, ]; t0 <- as.numeric(b$bucket)
    mid <- if (b$close >= b$open) c(b$low, b$high) else c(b$high, b$low)
    data.frame(ticker = b$ticker, ts = as.POSIXct(t0 + c(1, 20, 40, 59), origin = "1970-01-01", tz = "UTC"),
               price = c(b$open, mid, b$close), size = b$volume / 4,
               id = paste(b$ticker, t0, 1:4, sep = "-"))
  }))
}

# ---- live analytics ----

local_day <- function(ts, mk) as.Date(format(ts, "%Y-%m-%d", tz = LIVE$sessions[[mk]]$tz))
# Bars of the latest session with at least `min_bars` bars (else the one before it).
pick_session <- function(bars, mk, min_bars = 1) {
  d <- local_day(bars$bucket, mk); days <- sort(unique(d), decreasing = TRUE)
  n <- vapply(days, function(x) length(unique(bars$bucket[d == x])), 0)
  day <- if (any(n >= min_bars)) days[which(n >= min_bars)[1]] else days[1]
  bars[d == day, ]
}
# Change of the last price vs the previous session's close.
day_change <- function(bars, meta, mk) {
  cur <- pick_session(bars, mk); d <- local_day(bars$bucket, mk); prev <- bars[d < max(d), ]
  sapply(split(cur, cur$ticker), function(x) {
    tk <- x$ticker[1]; p <- prev[prev$ticker == tk, ]
    pc <- if (nrow(p)) p$close[which.max(p$bucket)] else meta[[tk]]$prev_close
    tail(x$close[order(x$bucket)], 1) / pc - 1 })
}


# Wide matrix of intraday log returns (rows = buckets, columns = tickers), last n buckets.
intraday_returns_wide <- function(bars, last_n = NULL) {
  bars <- bars[order(bars$ticker, bars$bucket), ]
  bars$r <- ave(log(bars$close), bars$ticker, FUN = function(x) c(NA, diff(x)))
  bk <- sort(unique(bars$bucket)); tk <- sort(unique(bars$ticker))
  R <- matrix(NA_real_, length(bk), length(tk), dimnames = list(format(bk), tk))
  R[cbind(match(bars$bucket, bk), match(bars$ticker, tk))] <- bars$r
  R <- R[-1, , drop = FALSE]
  if (!is.null(last_n) && nrow(R) > last_n) R <- R[(nrow(R) - last_n + 1):nrow(R), , drop = FALSE]
  R
}

# Correlation kNN graph on intraday returns (same construction as the research graph).
live_graph <- function(R, k = QS$knn_k, min_obs = 0.8) {
  ok <- colMeans(!is.na(R)) >= min_obs & apply(R, 2, function(x) stats::sd(x, na.rm = TRUE) > 0)
  if (sum(ok) < k + 2) return(NULL)
  rho <- suppressWarnings(stats::cor(R[, ok], use = "pairwise.complete.obs"))
  c(knn_graph(rho, k), list(tick = colnames(R)[ok], rho = rho, n_bars = nrow(R)))
}

# QSW node features on the live graph, as in the research (R/qsw_features.R):
#   q_self     return probability (how isolated the stock is on today's graph)
#   q_ent      entropy of the walk distribution (how widely risk spreads from it)
#   q_volspill walk-weighted mean of the other stocks' intraday volatility (spillover)
# (Column means of P are not reported: on a symmetric graph P is doubly stochastic,
# so they equal 1/N for every stock and carry no information.)
live_walk <- function(g, omega, rv = NULL, taus = QS$walk_time * seq_len(10) / 10) {
  P <- qsw_distributions(g$w, omega, taus, exact_limits = TRUE)
  P <- pmax(P, 0); P <- P / rowSums(P)
  out <- data.frame(ticker = g$tick, q_self = diag(P), q_ent = -rowSums(ifelse(P > 0, P * log(P), 0)))
  if (!is.null(rv)) {
    off <- P; diag(off) <- 0
    out$q_volspill <- as.numeric(off %*% rv[g$tick]) / pmax(rowSums(off), 1e-12)
  }
  attr(out, "P") <- P
  out
}

# Annualised realised volatility from intraday returns of the latest session.
intraday_rv <- function(bars, market) {
  bars <- bars[order(bars$ticker, bars$bucket), ]
  r <- ave(log(bars$close), bars$ticker, FUN = function(x) c(NA, diff(x)))
  v <- tapply(r, bars$ticker, function(x) mean(x^2, na.rm = TRUE))
  sqrt(v * LIVE$sessions[[market]]$bars_per_day * 252)
}

# ---- live graph-HAR volatility forecast ----

# GHAR coefficients fitted on the most recent `train_months` of the research data
# (all labels known by the fit date), exactly the specification of the paper's baseline.
ghar_live_model <- function(market, curated = QS$paths$curated, train_months = QS$train_months) {
  fg <- file.path(curated, "ghar_features.rds"); fv <- file.path(curated, "vol_targets.rds")
  if (!file.exists(fg) || !file.exists(fv)) return(NULL)
  gh <- readRDS(fg); vt <- readRDS(fv)
  d <- merge(vt, gh[gh$market == market, c("ticker", "date", "gh_d", "gh_w", "gh_m")], by = c("ticker", "date"))
  d <- d[stats::complete.cases(d[, c(GHAR_COLS, "y_lrv5")]), ]
  end <- max(d$label_date_rv)
  d <- d[d$date >= add_months(month_start(end), -train_months), ]
  b <- qr.coef(qr(cbind(1, as.matrix(d[, GHAR_COLS]))), d$y_lrv5); b[is.na(b)] <- 0
  list(coef = b, train_from = min(d$date), train_to = max(d$date), n = nrow(d))
}

# Forecast of the next-5-session volatility from completed daily sessions only: the bar of
# a session that is still trading is dropped, so the forecast never uses partial data.
ghar_live_forecast <- function(daily, model, market, now = Sys.time()) {
  st <- market_status(market, now)
  today <- as.Date(format(as.POSIXlt(now, tz = LIVE$sessions[[market]]$tz), "%Y-%m-%d"))
  if (st$open) daily <- daily[daily$date < today, ]
  gf <- ghar_features_market(daily); vt <- build_vol_targets(daily)
  d <- merge(vt[, c("ticker", "date", HAR_COLS)], gf, by = c("ticker", "date"))
  d <- d[stats::complete.cases(d[, GHAR_COLS]), ]
  # Each stock's own latest complete session (a missing bar for one stock must not drop it),
  # provided it is recent (within 7 days of the newest session).
  last <- ave(as.numeric(d$date), d$ticker, FUN = max)
  d <- d[as.numeric(d$date) == last & d$date >= max(d$date) - 7, ]
  pred <- as.numeric(cbind(1, as.matrix(d[, GHAR_COLS])) %*% model$coef)
  data.frame(ticker = d$ticker, as_of = d$date, pred_lrv5 = pred, vol5_ann = sqrt(exp(pred) * 252))
}
