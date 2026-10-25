# DuckDB backend for the live candle store, with Parquet history for old days.
# Same table (CANDLE_DDL, R/live_market.R) and contracts as the SQLite store; the
# dispatch on options(qstock.store_backend) lives in live_market.R.
# Gotchas: one read-write process per DuckDB file; close with
# DBI::dbDisconnect(con, shutdown = TRUE) so the file lock is released at once.

duck_store_open <- function(path, memory_limit = "128MB", threads = 1L) {
  if (path != ":memory:") dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  con <- DBI::dbConnect(duckdb::duckdb(dbdir = path, shared_home = FALSE))   # no extensions needed; silences the home-dir notice
  DBI::dbExecute(con, sprintf("SET memory_limit = '%s'", memory_limit))
  DBI::dbExecute(con, sprintf("SET threads = %d", as.integer(threads)))
  DBI::dbExecute(con, CANDLE_DDL)
  con
}

# Bulk idempotent upsert: one INSERT ... SELECT from a registered frame. Keys are made
# unique first (last row wins) because DuckDB refuses to update a row twice per command.
duck_upsert <- function(con, candles, interval_sec, source) {
  if (is.null(candles) || !nrow(candles)) return(c(written = 0L, rejected = 0L))
  ok <- with(candles, is.finite(open) & is.finite(close) & high >= pmax(open, close, low) & low <= pmin(open, close))
  ok[is.na(ok)] <- FALSE                                   # NA high/low is a bad bar, not an error
  if (!any(ok)) return(c(written = 0L, rejected = sum(!ok)))
  d <- candles[ok, ]
  d <- d[!duplicated(d[, c("ticker", "bucket")], fromLast = TRUE), ]
  df <- data.frame(ticker = as.character(d$ticker), interval_sec = as.integer(interval_sec),
                   bucket_start = as.numeric(d$bucket), open = d$open, high = d$high, low = d$low,
                   close = d$close, volume = as.numeric(d$volume), source = source,
                   updated_at = as.numeric(Sys.time()), stringsAsFactors = FALSE)
  tmp <- paste0("upsert_", paste(sample(letters, 10, TRUE), collapse = ""))
  duckdb::duckdb_register(con, tmp, df)
  on.exit(duckdb::duckdb_unregister(con, tmp))
  DBI::dbWithTransaction(con, DBI::dbExecute(con, sprintf(
    "INSERT INTO candles SELECT ticker, interval_sec, CAST(bucket_start AS BIGINT), open, high, low, close,
            volume, source, CAST(updated_at AS BIGINT) FROM %s
     ON CONFLICT (ticker, interval_sec, bucket_start) DO UPDATE SET
       open = excluded.open, high = excluded.high, low = excluded.low, close = excluded.close,
       volume = excluded.volume, source = excluded.source, updated_at = excluded.updated_at", tmp)))
  c(written = nrow(df), rejected = sum(!ok))
}

# ---- Parquet history helpers ----

duck_pq_glob <- function(dir) {
  if (is.null(dir) || !length(list.files(dir, "\\.parquet$", recursive = TRUE))) return(NULL)
  paste0(gsub("\\\\", "/", normalizePath(dir, mustWork = TRUE)), "/**/*.parquet")
}

# Partition columns come from the path; types are pinned so day prunes as a DATE.
duck_pq_from <- function(glob)
  sprintf("read_parquet('%s', hive_partitioning = true, hive_types = {'interval_sec': INTEGER, 'day': DATE})", glob)

DUCK_COLS <- "ticker, interval_sec, bucket_start, open, high, low, close, volume, source, updated_at"

# UTC day of an epoch second, as 'YYYY-MM-DD' (make_timestamp takes microseconds, no time zone).
DUCK_DAY <- "strftime(make_timestamp(bucket_start * 1000000), '%Y-%m-%d')"

day_utc <- function(x) format(as.POSIXct(pmin(pmax(x, -1e10), 1e10), origin = "1970-01-01", tz = "UTC"), "%Y-%m-%d")

# Range read [since, until) across table and Parquet; a table row wins over a Parquet row
# with the same key (late corrections after export).
duck_read <- function(con, ticker, interval_sec = 60, since = 0, until = Inf, parquet_dir = NULL) {
  ph <- paste(rep("?", length(ticker)), collapse = ", ")
  where <- sprintf("ticker IN (%s) AND interval_sec = ? AND bucket_start >= ? AND bucket_start < ?", ph)
  params <- c(as.list(as.character(ticker)), list(as.integer(interval_sec), as.numeric(since), as.numeric(until)))
  glob <- duck_pq_glob(parquet_dir)
  sql <- if (is.null(glob)) sprintf("SELECT * FROM candles WHERE %s ORDER BY ticker, bucket_start", where) else {
    sprintf("SELECT %s FROM (
               SELECT %s, 0 AS pri FROM candles WHERE %s
               UNION ALL
               SELECT %s, 1 AS pri FROM %s WHERE %s AND day >= CAST(? AS DATE) AND day <= CAST(? AS DATE))
             QUALIFY row_number() OVER (PARTITION BY ticker, interval_sec, bucket_start ORDER BY pri) = 1
             ORDER BY ticker, bucket_start", DUCK_COLS, DUCK_COLS, where, DUCK_COLS, duck_pq_from(glob), where)
  }
  if (!is.null(glob)) params <- c(params, params, list(day_utc(since), day_utc(until)))
  d <- DBI::dbGetQuery(con, sql, params = params)
  d$interval_sec <- as.integer(d$interval_sec)
  d$bucket <- as.POSIXct(d$bucket_start, origin = "1970-01-01", tz = "UTC")
  d
}

duck_stats <- function(con, interval_sec = 60, parquet_dir = NULL) {
  glob <- duck_pq_glob(parquet_dir)
  src <- if (is.null(glob)) "SELECT ticker, bucket_start FROM candles WHERE interval_sec = ?" else
    sprintf("SELECT ticker, bucket_start FROM candles WHERE interval_sec = ?
             UNION SELECT ticker, bucket_start FROM %s WHERE interval_sec = ?", duck_pq_from(glob))
  p <- rep(list(as.integer(interval_sec)), if (is.null(glob)) 1 else 2)
  r <- DBI::dbGetQuery(con, sprintf("SELECT COUNT(*) n, COUNT(DISTINCT ticker) t FROM (%s)", src), params = p)
  list(n = as.integer(r$n), t = as.integer(r$t))
}

# Move rows older than `before` to dir/interval_sec=<i>/day=YYYY-MM-DD/. Each affected day
# is rewritten whole (old Parquet rows + table rows, table wins), so re-export never
# duplicates. Returns the number of table rows moved.
duck_export_parquet <- function(con, dir, before) {
  before <- as.numeric(before)
  n <- DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM candles WHERE bucket_start < ?", params = list(before))$n
  if (!n) return(0L)
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  out <- gsub("\\\\", "/", normalizePath(dir, mustWork = TRUE))
  DBI::dbExecute(con, sprintf("CREATE OR REPLACE TEMP TABLE pq_out AS
    SELECT %s, 0 AS pri, %s AS day FROM candles WHERE bucket_start < ?", DUCK_COLS, DUCK_DAY), params = list(before))
  on.exit(DBI::dbExecute(con, "DROP TABLE IF EXISTS pq_out"))
  parts <- DBI::dbGetQuery(con, "SELECT DISTINCT interval_sec, day FROM pq_out")
  glob <- duck_pq_glob(dir)
  if (!is.null(glob))   # pull in what is already on disk for those days, materialised before the files go
    DBI::dbExecute(con, sprintf("INSERT INTO pq_out SELECT %s, 1 AS pri, strftime(p.day, '%%Y-%%m-%%d')
      FROM %s p SEMI JOIN (SELECT DISTINCT interval_sec, CAST(day AS DATE) d FROM pq_out) k
      ON p.interval_sec = k.interval_sec AND p.day = k.d", gsub("(\\w+)", "p.\\1", DUCK_COLS), duck_pq_from(glob)))
  unlink(file.path(dir, paste0("interval_sec=", parts$interval_sec), paste0("day=", parts$day)), recursive = TRUE)
  DBI::dbExecute(con, sprintf("COPY (SELECT %s, day FROM pq_out
      QUALIFY row_number() OVER (PARTITION BY ticker, interval_sec, bucket_start ORDER BY pri) = 1
      ORDER BY ticker, bucket_start)
    TO '%s' (FORMAT parquet, PARTITION_BY (interval_sec, day), COMPRESSION zstd, OVERWRITE_OR_IGNORE)", DUCK_COLS, out))
  DBI::dbExecute(con, "DELETE FROM candles WHERE bucket_start < ?", params = list(before))
  as.integer(n)
}
