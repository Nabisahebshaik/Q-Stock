# Build data/curated/prices.parquet from data/raw/prices_yahoo.csv and verify it.
# Run from the project root:  Rscript scripts/30_prices_to_parquet.R
# Re-runnable; the CSV is only read.

source("R/config.R"); source("R/data_adapter.R")
stopifnot(requireNamespace("duckdb", quietly = TRUE))

csv <- file.path(QS$paths$raw, "prices_yahoo.csv")
pq <- file.path(QS$paths$curated, "prices.parquet")
stopifnot(file.exists(csv))
dir.create(QS$paths$curated, recursive = TRUE, showWarnings = FALSE)

df_csv <- read_prices_csv(csv)
write_prices_parquet(df_csv, pq)
df_pq <- read_prices_parquet(pq)
ok <- identical(df_csv, df_pq)
cat(sprintf("rows: %d  cols: %d  identical(csv, parquet): %s\n", nrow(df_csv), ncol(df_csv), ok))
if (!ok) { print(all.equal(df_csv, df_pq)); stop("parquet frame differs from the CSV frame") }
stopifnot(identical(load_market_data(), df_csv))   # the loader now takes the Parquet path

mb <- function(f) file.size(f) / 2^20
cat(sprintf("size: CSV %.2f MB, Parquet %.2f MB (%.1fx smaller)\n", mb(csv), mb(pq), mb(csv) / mb(pq)))

time_med <- function(fun, n = 5) median(vapply(seq_len(n), function(i) system.time(fun())[["elapsed"]], 0))
t_csv <- time_med(function() read_prices_csv(csv))
t_pq <- time_med(function() read_prices_parquet(pq))
cat(sprintf("median load (5 runs): read.csv %.3f s, Parquet %.3f s (%.1fx faster)\n", t_csv, t_pq, t_csv / t_pq))
