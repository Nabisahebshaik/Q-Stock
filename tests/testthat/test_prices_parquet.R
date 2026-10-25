# Daily-price Parquet cache: exact round trip and CSV fallback. Offline, temp files only.

synthetic_prices <- function() {
  d <- as.Date("2024-01-01") + 0:5
  df <- data.frame(date = rep(d, 2), ticker = rep(c("AAA.NS", "BBB"), each = 6),
                   market = rep(c("NSE", "NASDAQ"), each = 6),
                   open = c(100.123456789012, 101:105, 50, 51:55 + 0.5), high = 110 + 0:11,
                   low = 90 + 0:11, close = 100 + (0:11) / 3, adj_close = 95 + (0:11) / 7,
                   volume = c(2963643, NA, 1e10, 4:12), stringsAsFactors = FALSE)
  # Go through the CSV like the real loader, so classes match read.csv exactly.
  f <- tempfile(fileext = ".csv"); on.exit(unlink(f))
  write.csv(df, f, row.names = FALSE)
  read_prices_csv(f)
}

test_that("prices parquet round trip is identical()", {
  skip_if_not_installed("duckdb")
  df <- synthetic_prices()
  pq <- tempfile(fileext = ".parquet"); on.exit(unlink(pq))
  write_prices_parquet(df, pq)
  back <- read_prices_parquet(pq)
  expect_identical(back, df)
  expect_identical(typeof(back$date), "double")
  expect_true(is.na(back$volume[2]))
})

test_that("load_market_data falls back to CSV without parquet, then caches it", {
  root <- tempfile("qs_"); dir.create(file.path(root, "raw"), recursive = TRUE)
  old <- QS$paths
  on.exit({ QS$paths <<- old; unlink(root, recursive = TRUE) })
  QS$paths$raw <<- file.path(root, "raw"); QS$paths$curated <<- file.path(root, "curated")
  df <- synthetic_prices()
  write.csv(df, file.path(QS$paths$raw, "prices_yahoo.csv"), row.names = FALSE)
  pq <- file.path(QS$paths$curated, "prices.parquet")
  expect_false(file.exists(pq))
  expect_identical(load_market_data(), df)            # CSV path (no curated dir yet)
  if (requireNamespace("duckdb", quietly = TRUE)) {
    expect_true(file.exists(pq))                       # cache written
    expect_identical(load_market_data(), df)          # Parquet path
    # A CSV newer than the Parquet wins.
    Sys.setFileTime(pq, Sys.time() - 3600)
    df2 <- df[1:3, ]; write.csv(df2, file.path(QS$paths$raw, "prices_yahoo.csv"), row.names = FALSE)
    expect_identical(load_market_data(), read_prices_csv(file.path(QS$paths$raw, "prices_yahoo.csv")))
    expect_equal(nrow(read_prices_parquet(pq)), 3)
  }
})
