# Real market-data adapter: daily OHLCV from the Yahoo Finance chart endpoint.
#
# Yahoo is an unofficial, free source. Adjusted prices are back-adjusted for
# splits/dividends using information known TODAY; this is standard for daily
# return studies, but it is not a point-in-time price feed. Returns computed
# from adjusted closes are unaffected by that adjustment except for rounding.

fetch_yahoo_daily <- function(symbol, from, to, market) {
  url <- sprintf(paste0("https://query1.finance.yahoo.com/v8/finance/chart/%s",
                        "?period1=%d&period2=%d&interval=1d&events=div%%2Csplit"),
                 utils::URLencode(symbol, reserved = TRUE),
                 as.integer(as.POSIXct(from, tz = "UTC")),
                 as.integer(as.POSIXct(to + 1, tz = "UTC")))
  h <- curl::new_handle(useragent = "Mozilla/5.0")
  resp <- curl::curl_fetch_memory(url, handle = h)
  if (resp$status_code != 200) stop(sprintf("%s: HTTP %d", symbol, resp$status_code))
  parse_yahoo_daily(rawToChar(resp$content), symbol, market)
}

# Parse a Yahoo chart-API daily JSON response (shared with the live module).
parse_yahoo_daily <- function(json_text, symbol, market) {
  js <- jsonlite::fromJSON(json_text, simplifyVector = TRUE)
  res <- js$chart$result
  if (is.null(res)) stop(sprintf("%s: empty result", symbol))
  q <- res$indicators$quote[[1]]
  num <- function(x) as.numeric(unlist(lapply(x, function(v) if (is.null(v)) NA else v)))
  # Exchange-local calendar date of each bar.
  ts <- unlist(res$timestamp) + res$meta$gmtoffset
  out <- data.frame(
    date = as.Date(as.POSIXct(ts, origin = "1970-01-01", tz = "UTC")),
    ticker = symbol, market = market,
    open = num(q$open), high = num(q$high), low = num(q$low), close = num(q$close),
    adj_close = num(res$indicators$adjclose[[1]]$adjclose),
    volume = num(q$volume)
  )
  out
}

# Basic validation and cleaning; returns the cleaned frame plus a log of issues.
clean_prices <- function(df) {
  issues <- list()
  n0 <- nrow(df)
  df <- df[!duplicated(df[, c("ticker", "date")], fromLast = TRUE), ]
  issues$duplicates <- n0 - nrow(df)
  bad <- !is.finite(df$close) | !is.finite(df$adj_close) | df$close <= 0 | df$adj_close <= 0
  issues$missing_or_nonpositive_close <- sum(bad)
  df <- df[!bad, ]
  # Adjust OHLC with the same factor as the close.
  f <- df$adj_close / df$close
  df$open <- ifelse(is.finite(df$open) & df$open > 0, df$open * f, df$adj_close)
  df$high <- ifelse(is.finite(df$high) & df$high > 0, df$high * f, df$adj_close)
  df$low  <- ifelse(is.finite(df$low) & df$low > 0, df$low * f, df$adj_close)
  df$high <- pmax(df$high, df$open, df$adj_close)
  df$low  <- pmin(df$low, df$open, df$adj_close)
  df$close <- df$adj_close
  df$adj_close <- NULL
  # Exchange holidays sometimes appear as bars with no volume for (almost) every
  # ticker. Drop a date when at least half of a market's tickers have no volume.
  novol <- !is.finite(df$volume) | df$volume <= 0
  share <- ave(as.numeric(novol), df$market, df$date, FUN = mean)
  holiday <- share >= 0.5
  issues$holiday_bars_dropped <- sum(holiday)
  issues$holiday_dates <- paste(sort(unique(paste(df$market[holiday], df$date[holiday]))), collapse = "; ")
  df <- df[!holiday, ]
  issues$zero_or_missing_volume <- sum(!is.finite(df$volume) | df$volume <= 0)
  df$volume[!is.finite(df$volume) | df$volume <= 0] <- NA
  # Flag (do not silently drop) extreme daily moves for manual review.
  df <- df[order(df$ticker, df$date), ]
  r <- ave(log(df$close), df$ticker, FUN = function(x) c(NA, diff(x)))
  issues$abs_logret_gt_0.4 <- sum(abs(r) > 0.4, na.rm = TRUE)
  rownames(df) <- NULL
  list(data = df, issues = issues)
}

# Daily-price Parquet cache (data/curated/prices.parquet). The frame read back is
# identical() to the CSV-loaded one, so research results reproduce exactly.
read_prices_csv <- function(f) {
  df <- read.csv(f, stringsAsFactors = FALSE)
  df$date <- as.Date(df$date)
  df
}

# Absolute forward-slash path with quotes escaped, for a DuckDB SQL literal.
sql_path <- function(path) gsub("'", "''", normalizePath(path, "/", mustWork = FALSE))

write_prices_parquet <- function(df, path) {
  con <- DBI::dbConnect(duck_drv())  # parquet is built in; no extensions needed
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  duckdb::duckdb_register(con, "prices_df", df)
  # Write a temp file and rename it, so a concurrent reader never sees a partial file.
  tmp <- paste0(path, ".tmp")
  DBI::dbExecute(con, sprintf("COPY (SELECT * FROM prices_df) TO '%s' (FORMAT parquet, COMPRESSION zstd)",
                              sql_path(tmp)))
  duckdb::duckdb_unregister(con, "prices_df")
  if (file.exists(path)) unlink(path)
  if (!file.rename(tmp, path)) { unlink(tmp); stop("could not move ", tmp, " to ", path) }
  invisible(path)
}

read_prices_parquet <- function(path) {
  con <- DBI::dbConnect(duck_drv())  # parquet is built in; no extensions needed
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  df <- DBI::dbGetQuery(con, sprintf("SELECT * FROM read_parquet('%s')", sql_path(path)))
  # Match read.csv + as.Date: double-backed Date, plain data.frame, automatic row names.
  for (j in names(df)) if (inherits(df[[j]], "Date"))
    df[[j]] <- structure(as.double(unclass(df[[j]])), class = "Date")
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  attr(df, "row.names") <- .set_row_names(nrow(df))
  df
}

# Best-effort cache write: a Parquet failure (or no duckdb) never breaks loading.
cache_prices_parquet <- function(df, pq) {
  if (!requireNamespace("duckdb", quietly = TRUE)) return(invisible(FALSE))
  tryCatch({
    dir.create(dirname(pq), recursive = TRUE, showWarnings = FALSE)
    write_prices_parquet(df, pq)
    invisible(TRUE)
  }, error = function(e) {
    message("prices parquet cache not written: ", conditionMessage(e))
    invisible(FALSE)
  })
}

load_market_data <- function(refresh = FALSE, pause = 0.5) {
  f <- file.path(QS$paths$raw, "prices_yahoo.csv")
  pq <- file.path(QS$paths$curated, "prices.parquet")
  if (file.exists(f) && !refresh) {
    # Parquet only when at least as new as the CSV (a rebuilt CSV invalidates it).
    if (file.exists(pq) && file.mtime(pq) >= file.mtime(f) &&
        requireNamespace("duckdb", quietly = TRUE)) {
      df <- tryCatch(read_prices_parquet(pq), error = function(e) NULL)
      if (!is.null(df)) return(df)
    }
    df <- read_prices_csv(f)
    cache_prices_parquet(df, pq)
    return(df)
  }
  dir.create(QS$paths$raw, recursive = TRUE, showWarnings = FALSE)
  parts <- list()
  for (mk in names(QS$universe)) for (sym in names(QS$universe[[mk]])) {
    message("fetching ", sym)
    parts[[sym]] <- fetch_yahoo_daily(sym, QS$start_date, QS$end_date, mk)
    Sys.sleep(pause)
  }
  df <- do.call(rbind, parts)
  write.csv(df, f, row.names = FALSE)
  # Cache the CSV-round-tripped frame: that is what later loads must reproduce.
  cache_prices_parquet(read_prices_csv(f), pq)
  df
}
