# Stage 3 (Spark part): distributed feature engineering with sparklyr (no PySpark).
#
# Compatibility finding (see docs/operations/environment_report.md): sparklyr 1.9.6 ships
# backend JARs only for Spark >= 2.4, so it cannot drive the VM's Spark 1.6.0.
# This script therefore runs Spark 3.5 in local mode on the host (Java 17).
#
# 1. Rolling return / volatility features with Spark window functions (dplyr).
# 2. Point-in-time sentiment join as a Spark SQL range join (bins t-21 .. t-1).
# 3. Cross-check both against the base-R implementations.
# 4. Scaling run: replicate the price table x1..x64 and time the Spark pipeline.

suppressPackageStartupMessages({ library(sparklyr); library(dplyr) })
if (Sys.getenv("JAVA_HOME") == "")
  Sys.setenv(JAVA_HOME = Sys.glob("C:/Program Files/Eclipse Adoptium/jdk-17*")[1])
# Windows: Hadoop's native IO needs winutils.exe + hadoop.dll (third-party build
# from github.com/cdarlint/winutils, hadoop-3.3.6) on HADOOP_HOME/bin and the JVM library path.
hadoop_home <- file.path(spark_install_find(version = "3.5")$sparkVersionDir, "tmp", "hadoop")
Sys.setenv(HADOOP_HOME = hadoop_home,
           PATH = paste(file.path(hadoop_home, "bin"), Sys.getenv("PATH"), sep = ";"))
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
ensure_dirs()

# Local mode: the executor lives inside the driver JVM, so only driver memory matters.
conf <- spark_config()
conf$`sparklyr.shell.driver-memory` <- "8G"
conf$`sparklyr.shell.driver-java-options` <-
  paste0("-Djava.library.path=", normalizePath(file.path(hadoop_home, "bin"), winslash = "/"))
conf$spark.sql.shuffle.partitions <- 16
conf$spark.ui.enabled <- FALSE
sc <- spark_connect(master = "local[8]", version = "3.5", config = conf)
cat("Spark version:", spark_version(sc) |> as.character(), "\n")

prices_sdf <- spark_read_csv(sc, "prices", path = normalizePath("data/curated/prices"),
                             memory = TRUE, null_value = "NA",
                             columns = c(market = "character", ticker = "character",
                                         date = "character", open = "double", high = "double",
                                         low = "double", close = "double", volume = "double",
                                         log_ret = "double"))

spark_features <- function(sdf) {
  sdf |>
    mutate(date = to_date(date)) |>
    group_by(ticker) |>
    dbplyr::window_order(date) |>
    mutate(rn = row_number(), lr = log(close) - lag(log(close))) |>
    dbplyr::window_frame(-4, 0) |> mutate(ret_5 = sum(lr, na.rm = TRUE)) |>
    dbplyr::window_frame(-19, 0) |>
    mutate(ret_20 = sum(lr, na.rm = TRUE), vol_20 = sd(lr, na.rm = TRUE)) |>
    ungroup() |>
    select(market, ticker, date, rn, close, lr, ret_5, ret_20, vol_20)
}

t0 <- Sys.time()
feat_sdf <- spark_features(prices_sdf) |> compute("spark_features")
n_feat <- sdf_nrow(feat_sdf)
t_feat <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
cat("Spark rolling features:", n_feat, "rows in", round(t_feat, 2), "s\n")

# ---- Point-in-time sentiment join (Spark SQL range join) ----
# Uses the combined GDELT file if the download has finished, otherwise whatever
# per-ticker files are cached (never triggers a new download from here).
sent_file <- file.path(QS$paths$raw, "sentiment_gdelt_daily.csv")
cache <- list.files(file.path(QS$paths$raw, "gdelt_cache"), full.names = TRUE)
sent <- if (file.exists(sent_file)) read.csv(sent_file) else do.call(rbind, lapply(cache, read.csv))
sent$day <- as.Date(sent$day)
cat("sentiment tickers available for the Spark join:", length(unique(sent$ticker)), "\n")
sent_sdf <- copy_to(sc, transform(sent, day = format(day))[, c("ticker", "day", "n_articles", "tone")],
                    "sentiment", overwrite = TRUE)
# a = age of the GDELT bin in days, 0 = UTC day t-1 (newest usable bin).
pit_sql <- "
SELECT ticker, date,
  COALESCE(SUM(CASE WHEN a < 3 THEN wt END) / NULLIF(SUM(CASE WHEN a < 3 THEN n END), 0), 0) AS sent_tone_3,
  COALESCE(SUM(CASE WHEN a < 7 THEN wt END) / NULLIF(SUM(CASE WHEN a < 7 THEN n END), 0), 0) AS sent_tone_7,
  COALESCE(SUM(CASE WHEN a < 9 THEN wt * POW(0.5, a / 3.0) END) /
           NULLIF(SUM(CASE WHEN a < 9 THEN n * POW(0.5, a / 3.0) END), 0), 0) AS sent_decay_3,
  COALESCE(SUM(wt * POW(0.5, a / 7.0)) / NULLIF(SUM(n * POW(0.5, a / 7.0)), 0), 0) AS sent_decay_7,
  LN(1 + COALESCE(SUM(CASE WHEN a < 7 THEN n END), 0)) AS sent_logvol_7
FROM (
  SELECT t.ticker, t.date, s.n, s.wt, DATEDIFF(DATE_SUB(t.date, 1), s.day) AS a
  FROM spark_features t
  LEFT JOIN (SELECT ticker, TO_DATE(day) AS day, CAST(n_articles AS DOUBLE) AS n,
                    COALESCE(tone, 0) * n_articles AS wt
             FROM sentiment) s
    ON t.ticker = s.ticker
   AND s.day BETWEEN DATE_SUB(t.date, 21) AND DATE_SUB(t.date, 1)) j
GROUP BY ticker, date"
t0 <- Sys.time()
pit_sdf <- sdf_sql(sc, pit_sql) |> compute("pit_sentiment")
n_pit <- sdf_nrow(pit_sdf)
t_pit <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
cat("Spark PIT sentiment join:", n_pit, "rows in", round(t_pit, 2), "s\n")

# ---- Cross-check against base R ----
sp <- collect(feat_sdf) |> as.data.frame()
sp$date <- as.Date(sp$date)
prices <- clean_prices(load_market_data())$data
rf <- build_features(prices)
cmp <- merge(sp, rf[, c("ticker", "date", "ret_5", "ret_20", "vol_20")],
             by = c("ticker", "date"), suffixes = c("_spark", "_r"))
cmp <- cmp[cmp$rn > 21, ]        # full windows only (first-row NA handling differs by design)
feat_diff <- c(ret_5 = max(abs(cmp$ret_5_spark - cmp$ret_5_r)),
               ret_20 = max(abs(cmp$ret_20_spark - cmp$ret_20_r)),
               vol_20 = max(abs(cmp$vol_20_spark - cmp$vol_20_r)))
print(signif(feat_diff, 3))

ps <- collect(pit_sdf) |> as.data.frame(); ps$date <- as.Date(ps$date)
rs <- sentiment_features(unique(sp[, c("ticker", "date")]), sent)
cmp2 <- merge(ps, rs, by = c("ticker", "date"), suffixes = c("_spark", "_r"))
sent_diff <- sapply(SENTIMENT_COLS, function(c)
  max(abs(cmp2[[paste0(c, "_spark")]] - cmp2[[paste0(c, "_r")]])))
print(signif(sent_diff, 3))

# ---- Scaling: replicate tickers k times ----
scale_rows <- list()
for (k in c(1, 4, 16, 64)) {
  rep_sdf <- sdf_sql(sc, sprintf(
    "SELECT p.market, CONCAT(p.ticker, '_r', CAST(r.id AS STRING)) AS ticker, p.date, p.open,
            p.high, p.low, p.close, p.volume, p.log_ret
     FROM prices p CROSS JOIN (SELECT id FROM RANGE(%d)) r", k)) |>
    sdf_repartition(16) |> compute(paste0("rep_", k))
  n <- sdf_nrow(rep_sdf)
  t0 <- Sys.time()
  out <- spark_features(rep_sdf) |> summarise(s = sum(vol_20, na.rm = TRUE)) |> collect()
  t_spark <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  t_r <- NA_real_
  if (k <= 16) {   # base R single-threaded reference on the same data
    loc <- prices[rep(seq_len(nrow(prices)), k), ]
    loc$ticker <- paste0(loc$ticker, "_r", rep(seq_len(k) - 1, each = nrow(prices)))
    t0 <- Sys.time(); invisible(build_features(loc))
    t_r <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  }
  scale_rows[[length(scale_rows) + 1]] <- data.frame(replication = k, rows = n,
                                                     spark_seconds = t_spark, base_r_seconds = t_r)
  print(tail(scale_rows, 1)[[1]])
  tbl_uncache(sc, paste0("rep_", k))
}
scale_df <- do.call(rbind, scale_rows)
write.csv(scale_df, file.path(QS$paths$tables, "spark_scaling.csv"), row.names = FALSE)

writeLines(c(
  paste("Spark version:", as.character(spark_version(sc))),
  paste("Java:", system2(file.path(Sys.getenv("JAVA_HOME"), "bin", "java"), "-version",
                         stdout = TRUE, stderr = TRUE)[1]),
  sprintf("Rolling features: %d rows, %.2f s", n_feat, t_feat),
  sprintf("PIT sentiment join: %d rows, %.2f s", n_pit, t_pit),
  sprintf("Spark vs R max |diff| (rows with full windows, n=%d): %s", nrow(cmp),
          paste(names(feat_diff), signif(feat_diff, 3), sep = "=", collapse = ", ")),
  sprintf("Spark vs R sentiment max |diff| (n=%d): %s", nrow(cmp2),
          paste(names(sent_diff), signif(sent_diff, 3), sep = "=", collapse = ", "))),
  file.path(QS$paths$results, "stage3_spark_log.txt"))
spark_disconnect(sc)
