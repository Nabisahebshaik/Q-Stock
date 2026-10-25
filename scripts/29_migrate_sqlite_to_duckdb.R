# Migrate the live candle store from SQLite to DuckDB, then move old days to Parquet.
#   1. copy every row of data/live/candles.sqlite (opened read-only, never modified; it is
#      the rollback copy) into data/live/candles.duckdb with the same CANDLE_DDL, via one
#      idempotent INSERT ... ON CONFLICT DO UPDATE;
#   2. verify row counts and per (ticker, interval_sec) checksums; exit 1 on mismatch;
#   3. export whole UTC days older than N days before the newest bucket to
#      data/live/parquet/interval_sec=<i>/day=YYYY-MM-DD/ (Hive, ZSTD), delete them from
#      DuckDB, and verify table rows + Parquet rows == source rows.
# Re-runnable: day partitions are rewritten whole, so Parquet rows are never duplicated.
# Run from the project root:
#   Rscript scripts/29_migrate_sqlite_to_duckdb.R [--export-before-days 7] [--force]
#     [--src data/live/candles.sqlite] [--db data/live/candles.duckdb] [--parquet-dir data/live/parquet]
# --force deletes the DuckDB file and the Parquet directory first (full rebuild).
# Paths can also be set with options(qstock.live_db_src = ..., qstock.live_db = ...).
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE))
  tryCatch(source(f), error = function(e) message("skip ", f, ": ", conditionMessage(e)))  # other modules may be mid-edit
if (!exists("CANDLE_DDL")) stop("CANDLE_DDL not found (R/live_market.R)")
suppressPackageStartupMessages({ library(DBI); library(duckdb) })

args <- commandArgs(trailingOnly = TRUE)
arg <- function(name, default) { i <- match(name, args); if (is.na(i) || i == length(args)) default else args[i + 1] }
src <- arg("--src", getOption("qstock.live_db_src", file.path("data", "live", "candles.sqlite")))
dst <- arg("--db", getOption("qstock.live_db", file.path("data", "live", "candles.duckdb")))
pq_dir <- arg("--parquet-dir", file.path(dirname(dst), "parquet"))
before_days <- as.numeric(arg("--export-before-days", 7))
force <- "--force" %in% args
if (!file.exists(src)) stop("source not found: ", src)
if (normalizePath(src, mustWork = FALSE) == normalizePath(dst, mustWork = FALSE)) stop("source and target are the same file")
fail <- function(...) { message("VERIFY FAILED: ", ...); quit(status = 1) }
mb <- function(p) sum(file.size(if (dir.exists(p)) list.files(p, recursive = TRUE, full.names = TRUE) else p), na.rm = TRUE) / 1e6
sq <- function(p) gsub("'", "''", normalizePath(p, winslash = "/", mustWork = FALSE))

if (force) { unlink(c(dst, paste0(dst, ".wal"))); unlink(pq_dir, recursive = TRUE) }
t0 <- Sys.time()

# ---- 1. copy ----
lite <- dbConnect(RSQLite::SQLite(), src, flags = RSQLite::SQLITE_RO)
rows <- dbGetQuery(lite, "SELECT * FROM candles")
dbDisconnect(lite)
rows$interval_sec <- as.integer(rows$interval_sec)
for (k in c("bucket_start", "updated_at")) rows[[k]] <- round(as.numeric(rows[[k]]))  # BIGINT columns
rows <- rows[!duplicated(rows[, c("ticker", "interval_sec", "bucket_start")], fromLast = TRUE), ]  # DuckDB updates a row once per command

con <- dbConnect(duckdb(shared_home = FALSE), dst)
on.exit(if (dbIsValid(con)) dbDisconnect(con, shutdown = TRUE), add = TRUE)
invisible(dbExecute(con, CANDLE_DDL))
duckdb_register(con, "src_rows", rows)
n_up <- dbExecute(con, "INSERT INTO candles SELECT ticker, interval_sec, bucket_start, open, high, low, close, volume, source, updated_at
                FROM src_rows ON CONFLICT (ticker, interval_sec, bucket_start) DO UPDATE SET
                  open = excluded.open, high = excluded.high, low = excluded.low, close = excluded.close,
                  volume = excluded.volume, source = excluded.source, updated_at = excluded.updated_at")

# ---- 2. verify copy (the table may also hold rows that a re-run will export again) ----
chk_sql <- "SELECT ticker, interval_sec, COUNT(*) AS n, MIN(bucket_start) AS mn, MAX(bucket_start) AS mx,
                   SUM(close) AS s_close, SUM(COALESCE(volume, 0)) AS s_vol FROM %s GROUP BY 1, 2"
compare <- function(a, b, what) {
  m <- merge(a, b, by = c("ticker", "interval_sec"), all = TRUE, suffixes = c(".a", ".b"))
  rel <- function(x, y) abs(x - y) / pmax(abs(x), abs(y), 1)
  bad <- is.na(m$n.a) | is.na(m$n.b) | m$n.a != m$n.b | m$mn.a != m$mn.b | m$mx.a != m$mx.b |
    rel(m$s_close.a, m$s_close.b) > 1e-9 | rel(m$s_vol.a, m$s_vol.b) > 1e-9
  if (any(bad)) { print(m[bad, ]); fail(what, ": ", sum(bad), " (ticker, interval) groups differ") }
  nrow(m)
}
ref <- dbGetQuery(con, sprintf(chk_sql, "src_rows"))
n_src <- nrow(rows)
n_db <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM candles")$n
if (n_db != n_src) fail("row count sqlite ", n_src, " vs duckdb ", n_db)
n_groups <- compare(ref, dbGetQuery(con, sprintf(chk_sql, "candles")), "sqlite vs duckdb")
cat(sprintf("copied %d rows (%d ticker x interval groups); counts and checksums match\n", n_src, n_groups))

# ---- 3. Parquet export of whole UTC days before (newest - N days) ----
day_expr <- "CAST(make_timestamp(bucket_start * 1000000) AS DATE)"  # UTC day; make_timestamp has no time zone
newest <- dbGetQuery(con, "SELECT MAX(bucket_start) AS m FROM candles")$m
cutoff_day <- as.Date(as.POSIXct(newest - before_days * 86400, origin = "1970-01-01", tz = "UTC"))
old <- dbGetQuery(con, sprintf("SELECT DISTINCT interval_sec, CAST(%s AS VARCHAR) AS day FROM candles
                                WHERE %s < DATE '%s' ORDER BY 1, 2", day_expr, day_expr, cutoff_day))
n_exp <- 0
if (nrow(old)) {
  # Rewrite each exported partition whole: drop its old files, then write it once.
  for (i in seq_len(nrow(old))) unlink(file.path(pq_dir, paste0("interval_sec=", old$interval_sec[i]), paste0("day=", old$day[i])), recursive = TRUE)
  dir.create(pq_dir, recursive = TRUE, showWarnings = FALSE)
  invisible(dbExecute(con, "SET preserve_insertion_order = true"))
  n_exp <- dbExecute(con, sprintf("COPY (SELECT *, %s AS day FROM candles WHERE %s < DATE '%s' ORDER BY ticker, interval_sec, bucket_start)
                          TO '%s' (FORMAT parquet, COMPRESSION zstd, PARTITION_BY (interval_sec, day), OVERWRITE_OR_IGNORE)",
                         day_expr, day_expr, cutoff_day, sq(pq_dir)))
  invisible(dbWithTransaction(con, dbExecute(con, sprintf("DELETE FROM candles WHERE %s < DATE '%s'", day_expr, cutoff_day))))
}
pq_glob <- sprintf("read_parquet('%s/**/*.parquet', hive_partitioning = true)", sq(pq_dir))
has_pq <- length(list.files(pq_dir, pattern = "\\.parquet$", recursive = TRUE)) > 0
n_tab <- dbGetQuery(con, "SELECT COUNT(*) AS n FROM candles")$n
n_pq <- if (has_pq) dbGetQuery(con, sprintf("SELECT COUNT(*) AS n FROM %s", pq_glob))$n else 0
if (n_tab + n_pq != n_src) fail("table ", n_tab, " + parquet ", n_pq, " != source ", n_src)
union_sql <- if (has_pq) sprintf("(SELECT ticker, CAST(interval_sec AS INTEGER) AS interval_sec, bucket_start, close, volume FROM %s
                                   UNION ALL SELECT ticker, interval_sec, bucket_start, close, volume FROM candles)", pq_glob) else "candles"
invisible(compare(ref, dbGetQuery(con, sprintf(chk_sql, union_sql)), "sqlite vs duckdb + parquet"))
invisible(dbExecute(con, "CHECKPOINT"))
invisible(duckdb_unregister(con, "src_rows"))

span <- dbGetQuery(con, "SELECT MIN(bucket_start) AS a, MAX(bucket_start) AS b FROM candles")
dbDisconnect(con, shutdown = TRUE)

# DuckDB does not shrink a file after DELETE (a re-run re-inserts and re-deletes the old
# days), so rewrite it compactly; COPY FROM DATABASE keeps the schema and constraints.
if (n_exp > 0) {
  tmp <- paste0(dst, ".compact"); unlink(tmp)
  cc <- dbConnect(duckdb(shared_home = FALSE))
  invisible(dbExecute(cc, sprintf("ATTACH '%s' AS a (READ_ONLY)", sq(dst))))
  invisible(dbExecute(cc, sprintf("ATTACH '%s' AS b", sq(tmp))))
  invisible(dbExecute(cc, "COPY FROM DATABASE a TO b"))
  n_cc <- dbGetQuery(cc, "SELECT COUNT(*) AS n FROM b.candles")$n
  dbDisconnect(cc, shutdown = TRUE)
  if (n_cc != n_tab) fail("compacted copy has ", n_cc, " rows, expected ", n_tab)
  if (!file.rename(tmp, dst)) fail("could not replace ", dst, " with the compacted copy")
}

# ---- summary ----
ts <- function(x) format(as.POSIXct(x, origin = "1970-01-01", tz = "UTC"), "%Y-%m-%d %H:%M UTC")
cat(sprintf("source   %s: %d rows, %.2f MB\n", src, n_src, mb(src)))
cat(sprintf("duckdb   %s: %d rows (%s .. %s), %.2f MB\n", dst, n_tab, ts(span$a), ts(span$b), mb(dst)))
cat(sprintf("parquet  %s: %d rows in %d day partitions (days < %s, i.e. > %g days before newest %s), %.2f MB\n",
            pq_dir, n_pq, length(list.files(pq_dir, pattern = "^day=", include.dirs = TRUE, recursive = TRUE)),
            cutoff_day, before_days, ts(newest), mb(pq_dir)))
cat(sprintf("verified: table + parquet = source = %d rows; checksums match. %.1f s\n", n_src, as.numeric(difftime(Sys.time(), t0, units = "secs"))))
