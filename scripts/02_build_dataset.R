# Stage 2: real data -> cleaned prices -> classical + market-graph walk features.
# Run from the project root:  Rscript scripts/02_build_dataset.R
# Sentiment is merged later (05_experiments.R) because its download is slow.

for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
ensure_dirs()
dir.create(QS$paths$curated, showWarnings = FALSE)

raw <- load_market_data()
cl <- clean_prices(raw)
prices <- cl$data
cat("Cleaning report:\n"); str(cl$issues)

# List extreme moves for manual inspection (they are kept, not dropped).
prices <- prices[order(prices$ticker, prices$date), ]
r <- ave(log(prices$close), prices$ticker, FUN = function(x) c(NA, diff(x)))
ext <- prices[which(abs(r) > 0.4), c("ticker", "date", "close")]
ext$log_ret <- r[which(abs(r) > 0.4)]
print(ext)

t0 <- Sys.time()
ds <- build_dataset(prices, sent = NULL)
cat("dataset built in", round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1), "s\n")
saveRDS(ds, file.path(QS$paths$curated, "dataset_graph.rds"))

summary_tbl <- do.call(rbind, lapply(split(ds, ds$market), function(d) data.frame(
  market = d$market[1], rows = nrow(d), tickers = length(unique(d$ticker)),
  first_date = format(min(d$date)), last_date = format(max(d$date)),
  share_up = round(mean(d$y_up), 4), share_high_vol_regime = round(mean(d$regime_hi, na.rm = TRUE), 4))))
print(summary_tbl)
write.csv(summary_tbl, file.path(QS$paths$tables, "dataset_summary.csv"), row.names = FALSE)
writeLines(c(capture.output(str(cl$issues)), "", "Extreme moves (|log return| > 0.4):",
             capture.output(print(ext))), file.path(QS$paths$results, "data_quality_report.txt"))
