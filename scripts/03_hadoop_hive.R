# Stage 3: HDFS storage, Hadoop MapReduce aggregation and Hive tables/queries on
# the Cloudera QuickStart VM. Run from the project root after 02_build_dataset.R
# (and again after 05_experiments.R to load the results tables).
#
# Requires: VM running, SSH key access on host port 2222 (see docs/runbook.md).

for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
ensure_dirs()
HDFS_ROOT <- "/user/cloudera/qstock"
log_lines <- character()
note <- function(...) { s <- paste0(...); message(s); log_lines <<- c(log_lines, s) }

# ---- 1. Curated prices -> HDFS (one file per market => several input splits) ----
prices <- clean_prices(load_market_data())$data
prices <- prices[order(prices$market, prices$ticker, prices$date), ]
prices$log_ret <- ave(log(prices$close), prices$ticker, FUN = function(x) c(NA, diff(x)))
cur_dir <- file.path(QS$paths$curated, "prices"); dir.create(cur_dir, recursive = TRUE, showWarnings = FALSE)
for (mk in unique(prices$market)) {
  d <- prices[prices$market == mk, c("market", "ticker", "date", "open", "high", "low",
                                      "close", "volume", "log_ret")]
  d$date <- format(d$date)
  write.csv(d, file.path(cur_dir, paste0("prices_", mk, ".csv")), row.names = FALSE,
            quote = FALSE, na = "NA")
}

for (p in c("curated/prices", "raw/sentiment", "code", "mr", "results/experiments",
            "results/predictions"))
  hdfs_mkdirs(file.path(HDFS_ROOT, p))
for (f in list.files(cur_dir, full.names = TRUE))
  hdfs_put(f, file.path(HDFS_ROOT, "curated/prices", basename(f)))
sent_file <- file.path(QS$paths$raw, "sentiment_gdelt_daily.csv")
if (file.exists(sent_file)) hdfs_put(sent_file, file.path(HDFS_ROOT, "raw/sentiment/sentiment_gdelt_daily.csv"))
for (f in c("hadoop/QStockMonthlyStats.java", list.files("hive", full.names = TRUE)))
  hdfs_put(f, file.path(HDFS_ROOT, "code", basename(f)))
ls_prices <- hdfs_ls(file.path(HDFS_ROOT, "curated/prices"))
print(ls_prices)
note("HDFS curated prices: ", nrow(ls_prices), " files, ", sum(ls_prices$size), " bytes, replication ",
     paste(unique(ls_prices$replication), collapse = "/"), ", block size ",
     unique(ls_prices$block_size) / 2^20, " MB")

# ---- 2. Compile and run the MapReduce job on YARN ----
mr_out <- file.path(HDFS_ROOT, "mr/monthly_stats")
t0 <- Sys.time()
mr_log <- vm_ssh(paste(
  "set -e; rm -rf ~/qstock_build && mkdir -p ~/qstock_build/classes && cd ~/qstock_build",
  sprintf("&& hdfs dfs -get %s/code/QStockMonthlyStats.java .", HDFS_ROOT),
  "&& javac -cp $(hadoop classpath) -d classes QStockMonthlyStats.java",
  "&& jar cf qstock-mr.jar -C classes .",
  sprintf("&& (hdfs dfs -rm -r -f -skipTrash %s || true)", mr_out),
  sprintf("&& hadoop jar qstock-mr.jar QStockMonthlyStats %s/curated/prices %s 2>&1", HDFS_ROOT, mr_out)),
  echo = FALSE)
note("MapReduce wall time (incl. compile): ", round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1), " s")
writeLines(mr_log, file.path(QS$paths$results, "mapreduce_job.log"))
keep <- grep("Job job_|completed successfully|Map input records|Map output records|Combine (input|output) records|Reduce input records|Reduce output records|mapped_rows|skipped_rows|Launched (map|reduce) tasks",
             mr_log, value = TRUE)
note(paste(trimws(keep), collapse = "\n"))

# ---- 3. Validate MapReduce output against an independent R computation ----
parts <- hdfs_ls(mr_out); parts <- parts$name[grepl("^part-", parts$name)]
mr <- do.call(rbind, lapply(parts, function(p)
  read.delim(text = hdfs_get_text(file.path(mr_out, p)), header = FALSE,
             col.names = c("market", "ticker", "month", "n_days", "month_log_ret",
                           "mean_log_ret", "realized_vol_ann", "total_volume"))))
pr <- prices[!is.na(prices$log_ret), ]; pr$month <- format(pr$date, "%Y-%m")
ref <- aggregate(log_ret ~ market + ticker + month, pr, function(x)
  c(n = length(x), s = sum(x), v = if (length(x) > 1) sd(x) * sqrt(252) else 0))
ref <- data.frame(ref[, 1:3], ref$log_ret)
chk <- merge(mr, ref, by = c("market", "ticker", "month"))
note("MR rows: ", nrow(mr), "; R reference rows: ", nrow(ref), "; matched: ", nrow(chk))
note("max |n diff| = ", max(abs(chk$n_days - chk$n)),
     "; max |sum diff| = ", signif(max(abs(chk$month_log_ret - chk$s)), 3),
     "; max |vol diff| = ", signif(max(abs(chk$realized_vol_ann - chk$v)), 3))
write.csv(mr, file.path(QS$paths$tables, "mr_monthly_stats.csv"), row.names = FALSE)

# ---- 4. Hive: tables + queries via beeline ----
beeline <- function(hql_file, out_name) {
  out <- vm_ssh(paste(
    "set -e; cd ~/qstock_build",
    sprintf("&& rm -f %s && hdfs dfs -get %s/code/%s .", hql_file, HDFS_ROOT, hql_file),   # Hadoop 2.6 -get has no -f
    sprintf("&& beeline -u jdbc:hive2://localhost:10000 -n cloudera --silent=true --showHeader=true --outputformat=tsv2 -f %s 2>/dev/null", hql_file)),
    echo = FALSE)
  if (!is.null(out_name)) writeLines(out, file.path(QS$paths$tables, out_name))
  out
}
t0 <- Sys.time()
beeline("01_market_tables.hql", NULL)
q <- beeline("03_market_queries.hql", "hive_market_queries.tsv")
note("Hive market tables + 5 queries: ", round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1), " s")
note(paste(q, collapse = "\n"))

# ---- 5. Results tables (only after 05_experiments.R has produced them) ----
res_file <- file.path(QS$paths$tables, "experiment_results.csv")
pred_file <- file.path(QS$paths$tables, "predictions_main.csv")
if (file.exists(res_file) && file.exists(pred_file)) {
  hdfs_put(res_file, file.path(HDFS_ROOT, "results/experiments/experiment_results.csv"))
  hdfs_put(pred_file, file.path(HDFS_ROOT, "results/predictions/predictions_main.csv"))
  beeline("02_results_tables.hql", NULL)
  r <- beeline("04_results_queries.hql", "hive_results_queries.tsv")
  note(paste(r, collapse = "\n"))
} else note("experiment results not found yet; skipped Hive results tables")

writeLines(log_lines, file.path(QS$paths$results, "stage3_hadoop_hive_log.txt"))
