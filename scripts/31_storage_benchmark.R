# Storage benchmark: SQLite vs DuckDB vs Parquet for the live candle queries and the daily
# price load. SQLite reads data/live/candles.sqlite read-only; DuckDB uses a temporary full
# copy (no Parquet export, so it holds every row); Parquet is read_parquet over a temporary
# Hive export of ALL rows. Median of 20 timed runs after one warm-up run (bench::mark).
# Writes results/tables/storage_benchmark.csv (query, engine, median_ms, rows).
# Run from the project root:
#   Rscript scripts/31_storage_benchmark.R
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE))
  tryCatch(source(f), error = function(e) message("skip ", f, ": ", conditionMessage(e)))  # other modules may be mid-edit
if (!exists("CANDLE_DDL")) stop("CANDLE_DDL not found (R/live_market.R)")
suppressPackageStartupMessages({ library(DBI); library(duckdb) })

src <- getOption("qstock.live_db_src", file.path("data", "live", "candles.sqlite"))
prices_csv <- file.path("data", "raw", "prices_yahoo.csv")
tmp <- file.path(tempdir(), "qstock_bench"); unlink(tmp, recursive = TRUE); dir.create(tmp)
sq <- function(p) gsub("'", "''", normalizePath(p, winslash = "/", mustWork = FALSE))
mb <- function(p) sum(file.size(if (dir.exists(p)) list.files(p, recursive = TRUE, full.names = TRUE) else p)) / 1e6
n_iter <- 20L

# ---- build the three stores ----
lite <- dbConnect(RSQLite::SQLite(), src, flags = RSQLite::SQLITE_RO)
rows <- dbGetQuery(lite, "SELECT * FROM candles")
rows$interval_sec <- as.integer(rows$interval_sec)
for (k in c("bucket_start", "updated_at")) rows[[k]] <- round(as.numeric(rows[[k]]))
duck_path <- file.path(tmp, "candles_full.duckdb")
duck <- dbConnect(duckdb(shared_home = FALSE), duck_path)
invisible(dbExecute(duck, CANDLE_DDL))
duckdb_register(duck, "src_rows", rows)
invisible(dbExecute(duck, "INSERT INTO candles SELECT * FROM src_rows"))
duckdb_unregister(duck, "src_rows")
invisible(dbExecute(duck, "CHECKPOINT"))
pq_dir <- file.path(tmp, "parquet")
invisible(dbExecute(duck, sprintf("COPY (SELECT *, CAST(make_timestamp(bucket_start * 1000000) AS DATE) AS day FROM candles
                                   ORDER BY ticker, interval_sec, bucket_start)
                                   TO '%s' (FORMAT parquet, COMPRESSION zstd, PARTITION_BY (interval_sec, day))", sq(pq_dir))))
pqc <- dbConnect(duckdb(shared_home = FALSE))  # in-memory engine that only reads the Parquet files
invisible(dbExecute(pqc, sprintf("CREATE VIEW candles AS SELECT ticker, CAST(interval_sec AS INTEGER) AS interval_sec, bucket_start,
                                  open, high, low, close, volume, source, updated_at
                                  FROM read_parquet('%s/**/*.parquet', hive_partitioning = true)", sq(pq_dir))))
engines <- list(sqlite = lite, duckdb = duck, parquet = pqc)

# ---- query parameters (UTC day = one session for both NSE and NASDAQ) ----
day_start <- function(x) x - x %% 86400
tk <- "AAPL"
tk_days <- sort(unique(day_start(rows$bucket_start[rows$ticker == tk])), decreasing = TRUE)
nse <- sort(unique(rows$ticker[grepl("\\.NS$", rows$ticker)]))
nse_since <- max(day_start(rows$bucket_start[rows$ticker %in% nse]))
in_list <- paste0("'", nse, "'", collapse = ", ")
# Same SQL for every engine; day = bucket_start - bucket_start % 86400 works in both dialects.
queries <- list(
  a_chart_latest_session = sprintf("SELECT * FROM candles WHERE ticker = '%s' AND interval_sec = 60 AND bucket_start >= %.0f ORDER BY bucket_start", tk, tk_days[1]),
  b_one_ticker_5_sessions = sprintf("SELECT * FROM candles WHERE ticker = '%s' AND interval_sec = 60 AND bucket_start >= %.0f ORDER BY bucket_start", tk, tk_days[min(5, length(tk_days))]),
  c_market_latest_session = sprintf("SELECT * FROM candles WHERE ticker IN (%s) AND interval_sec = 60 AND bucket_start >= %.0f ORDER BY ticker, bucket_start", in_list, nse_since),
  d_daily_rollup = "SELECT ticker, day, MIN(o) AS open, MAX(high) AS high, MIN(low) AS low, MIN(c) AS close, SUM(volume) AS volume, COUNT(*) AS n
    FROM (SELECT ticker, bucket_start - bucket_start % 86400 AS day, high, low, volume,
                 FIRST_VALUE(open) OVER w AS o, LAST_VALUE(close) OVER w AS c
          FROM candles WHERE interval_sec = 60
          WINDOW w AS (PARTITION BY ticker, bucket_start - bucket_start % 86400 ORDER BY bucket_start
                       ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)) t
    GROUP BY ticker, day ORDER BY ticker, day")
duck_native_rollup <- "SELECT ticker, bucket_start - bucket_start % 86400 AS day, arg_min(open, bucket_start) AS open, MAX(high) AS high,
    MIN(low) AS low, arg_max(close, bucket_start) AS close, SUM(volume) AS volume, COUNT(*) AS n
    FROM candles WHERE interval_sec = 60 GROUP BY 1, 2 ORDER BY 1, 2"

time_it <- function(fn) {
  n <- NROW(fn())  # warm-up (also loads pages / file metadata into cache)
  b <- bench::mark(fn(), iterations = n_iter, check = FALSE, memory = FALSE, filter_gc = FALSE)
  c(median_ms = as.numeric(b$median) * 1000, rows = n)
}
res <- list(); add <- function(q, e, fn) { r <- time_it(fn); res[[length(res) + 1]] <<- data.frame(query = q, engine = e, median_ms = round(r[["median_ms"]], 3), rows = r[["rows"]]); cat(sprintf("%-26s %-22s %9.3f ms %7d rows\n", q, e, r[["median_ms"]], r[["rows"]])) }

for (q in names(queries)) for (e in names(engines)) local({ con <- engines[[e]]; sql <- queries[[q]]; add(q, e, function() dbGetQuery(con, sql)) })
add("d_daily_rollup", "duckdb_arg_min_max", function() dbGetQuery(duck, duck_native_rollup))
add("d_daily_rollup", "parquet_arg_min_max", function() dbGetQuery(pqc, duck_native_rollup))
# Chart query including connect + disconnect: the cost a request pays without a pooled connection.
add("a_chart_latest_session", "sqlite_with_connect", function() { c1 <- dbConnect(RSQLite::SQLite(), src, flags = RSQLite::SQLITE_RO); on.exit(dbDisconnect(c1)); dbGetQuery(c1, queries$a_chart_latest_session) })
dbDisconnect(duck, shutdown = TRUE)  # a DuckDB file has one read-write process; reopen per call read-only
add("a_chart_latest_session", "duckdb_with_connect", function() { c1 <- dbConnect(duckdb(shared_home = FALSE), duck_path, read_only = TRUE); on.exit(dbDisconnect(c1, shutdown = TRUE)); dbGetQuery(c1, queries$a_chart_latest_session) })

# ---- e) daily prices: CSV vs Parquet ----
prices <- read.csv(prices_csv)
prices_pq <- file.path(tmp, "prices.parquet")
duckdb_register(pqc, "prices_df", prices)
invisible(dbExecute(pqc, sprintf("COPY prices_df TO '%s' (FORMAT parquet, COMPRESSION zstd)", sq(prices_pq))))
duckdb_unregister(pqc, "prices_df")
add("e_daily_prices_load", "csv_read.csv", function() read.csv(prices_csv))
add("e_daily_prices_load", "duckdb_read_csv", function() dbGetQuery(pqc, sprintf("SELECT * FROM read_csv('%s')", sq(prices_csv))))
add("e_daily_prices_load", "parquet", function() dbGetQuery(pqc, sprintf("SELECT * FROM read_parquet('%s')", sq(prices_pq))))
dbDisconnect(lite); dbDisconnect(pqc, shutdown = TRUE)

out <- do.call(rbind, res)
dir.create(file.path("results", "tables"), recursive = TRUE, showWarnings = FALSE)
write.csv(out, file.path("results", "tables", "storage_benchmark.csv"), row.names = FALSE)
cat("\n"); print(out, row.names = FALSE)
cat(sprintf("\ncandles: %d rows, %d tickers | sqlite %.2f MB | duckdb (full copy) %.2f MB | parquet (all rows, %d day partitions) %.2f MB\n",
            nrow(rows), length(unique(rows$ticker)), mb(src), mb(duck_path),
            length(list.files(pq_dir, pattern = "\\.parquet$", recursive = TRUE)), mb(pq_dir)))
cat(sprintf("prices:  %d rows | csv %.2f MB | parquet %.2f MB\n", nrow(prices), mb(prices_csv), mb(prices_pq)))
cat(sprintf("R %s, DuckDB %s, RSQLite %s (SQLite %s); %d runs per cell\n", getRversion(), packageVersion("duckdb"),
            packageVersion("RSQLite"), RSQLite::rsqliteVersion()[2], n_iter))
unlink(tmp, recursive = TRUE)
