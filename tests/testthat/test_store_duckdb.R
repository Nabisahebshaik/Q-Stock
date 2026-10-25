# DuckDB candle store and Parquet history: same semantics as the SQLite store.
# Offline; files go to tempdir().

utc <- function(s) as.POSIXct(s, tz = "UTC")

bars <- function(tk = "A", t0 = "2026-10-23 05:00:00", n = 3) {
  o <- 10 + seq_len(n) * 0.1
  data.frame(ticker = tk, bucket = utc(t0) + 60 * (seq_len(n) - 1), open = o, high = o + 0.5,
             low = o - 0.5, close = o + 0.2, volume = seq_len(n) * 10, stringsAsFactors = FALSE)
}

duck_mem <- function() duck_store_open(":memory:")
close_duck <- function(con) DBI::dbDisconnect(con, shutdown = TRUE)
pq_tmp <- function() { d <- tempfile("pq_"); dir.create(d); d }
ohlcv <- function(d) d[, c("ticker", "bucket_start", "open", "high", "low", "close", "volume")]

test_that("duck upsert is idempotent and a late correction replaces values", {
  con <- duck_mem(); on.exit(close_duck(con))
  b <- bars()
  expect_equal(unname(duck_upsert(con, b, 60, "test")), c(3, 0))
  duck_upsert(con, b, 60, "test")                                         # replay
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM candles")$n, 3)
  c2 <- b[2, ]; c2$close <- 10.6; c2$high <- 10.9
  duck_upsert(con, c2, 60, "late")
  r <- duck_read(con, "A", 60)
  expect_equal(r$close[2], 10.6); expect_equal(r$high[2], 10.9); expect_equal(r$source[2], "late")
  expect_equal(r$bucket, b$bucket); expect_s3_class(r$bucket, "POSIXct")
})

test_that("bad OHLC bars are counted and never stored; all-rejected returns early", {
  con <- duck_mem(); on.exit(close_duck(con))
  b <- bars(); b$high[2] <- 5                                              # high < low
  expect_equal(unname(duck_upsert(con, b, 60, "test")), c(2, 1))
  expect_equal(nrow(duck_read(con, "A", 60)), 2)
  bad <- bars(n = 2); bad$high <- 1
  expect_equal(unname(duck_upsert(con, bad, 60, "test")), c(0, 2))
  expect_equal(unname(duck_upsert(con, NULL, 60, "test")), c(0, 0))
  expect_equal(unname(duck_upsert(con, bad[0, ], 60, "test")), c(0, 0))
})

test_that("duplicate keys in one batch keep the last row", {
  con <- duck_mem(); on.exit(close_duck(con))
  b <- bars(n = 2); d <- b[2, ]; d$close <- 10.65
  expect_equal(unname(duck_upsert(con, rbind(b, d), 60, "test")), c(2, 0))
  expect_equal(duck_read(con, "A", 60)$close, c(b$close[1], 10.65))
})

test_that("read takes a ticker vector and since/until filters, and is empty but typed on no match", {
  con <- duck_mem(); on.exit(close_duck(con))
  duck_upsert(con, rbind(bars("B"), bars("A"), bars("C")), 60, "test")
  r <- duck_read(con, c("B", "A"), 60)
  expect_equal(r$ticker, rep(c("A", "B"), each = 3))
  t0 <- as.numeric(utc("2026-10-23 05:00:00"))
  r <- duck_read(con, "A", 60, since = t0 + 60, until = t0 + 120)          # [since, until)
  expect_equal(r$bucket_start, t0 + 60)
  e <- duck_read(con, "Z", 60)
  expect_equal(nrow(e), 0)
  expect_true(all(c("ticker", "bucket_start", "close", "bucket") %in% names(e)))
})

test_that("export to Parquet then read back gives identical rows; re-export does not duplicate", {
  con <- duck_mem(); on.exit(close_duck(con))
  dir <- pq_tmp()
  old <- rbind(bars("A", "2026-10-22 05:00:00"), bars("B", "2026-10-22 05:00:00"))
  new <- bars("A", "2026-10-23 05:00:00")
  duck_upsert(con, rbind(old, new), 60, "test")
  before <- duck_read(con, c("A", "B"), 60)
  cut <- as.numeric(utc("2026-10-23 00:00:00"))
  expect_equal(duck_export_parquet(con, dir, cut), 6L)
  expect_true(dir.exists(file.path(dir, "interval_sec=60", "day=2026-10-22")))
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM candles")$n, 3)
  after <- duck_read(con, c("A", "B"), 60, parquet_dir = dir)
  expect_equal(after[, names(before)], before, ignore_attr = TRUE)
  expect_equal(duck_stats(con, 60, dir), list(n = 9L, t = 2L))
  expect_equal(duck_stats(con, 60), list(n = 3L, t = 1L))

  # replay old day into the table (with a correction) and export again: still one copy per key
  fix <- old; fix$close[1] <- fix$close[1] + 0.1
  duck_upsert(con, fix, 60, "test")
  expect_equal(duck_stats(con, 60, dir)$n, 9L)                              # union dedupes
  r <- duck_read(con, "A", 60, parquet_dir = dir)
  expect_equal(r$close[1], fix$close[1])                                    # table row wins
  expect_equal(duck_export_parquet(con, dir, cut), 6L)
  expect_equal(duck_export_parquet(con, dir, cut), 0L)
  r <- duck_read(con, c("A", "B"), 60, parquet_dir = dir)
  expect_equal(nrow(r), 9); expect_equal(r$close[1], fix$close[1])
  n_pq <- DBI::dbGetQuery(con, sprintf("SELECT COUNT(*) n FROM %s", duck_pq_from(duck_pq_glob(dir))))$n
  expect_equal(n_pq, 6)
  # day pruning: a range on the new day only
  r <- duck_read(con, "A", 60, since = cut, parquet_dir = dir)
  expect_equal(nrow(r), 3)
})

test_that("file-backed store persists across reopen", {
  path <- tempfile("candles_", fileext = ".duckdb")
  con <- duck_store_open(path); duck_upsert(con, bars(), 60, "test"); close_duck(con)
  con <- duck_store_open(path); on.exit(close_duck(con))
  expect_equal(nrow(duck_read(con, "A", 60)), 3)
})

test_that("DuckDB and SQLite stores give the same OHLCV for the same input", {
  set.seed(7)
  b <- do.call(rbind, lapply(c("A", "B"), function(tk) {
    x <- bars(tk, n = 30); x$close <- x$close + runif(30, -0.2, 0.2); x }))
  b$high[5] <- 1                                                          # one rejected bar
  b <- rbind(b, transform(b[3, ], close = b$close[3] + 0.05))              # a revision in a later batch
  sq <- candle_store_open(":memory:"); on.exit(DBI::dbDisconnect(sq))
  dk <- duck_mem(); on.exit(close_duck(dk), add = TRUE)
  rs <- candle_upsert(sq, b[1:60, ], 60, "test"); candle_upsert(sq, b[61, ], 60, "test")
  rd <- duck_upsert(dk, b[1:60, ], 60, "test"); duck_upsert(dk, b[61, ], 60, "test")
  expect_equal(rd, rs)
  s <- rbind(candle_read(sq, "A", 60), candle_read(sq, "B", 60))
  d <- duck_read(dk, c("A", "B"), 60)
  expect_equal(ohlcv(d), ohlcv(s), ignore_attr = TRUE)
  expect_equal(d$bucket, s$bucket)
})
