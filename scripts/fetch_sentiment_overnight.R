# Patient GDELT download: keeps retrying (per-ticker cache, so progress is kept)
# with long pauses after rate-limit failures, until all tickers are fetched or
# the time budget runs out. Exit status 0 only if the combined file exists.
#   Rscript scripts/fetch_sentiment_overnight.R [hours=14]

for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
hours <- as.numeric(commandArgs(trailingOnly = TRUE)[1]); if (is.na(hours)) hours <- 14
deadline <- Sys.time() + hours * 3600
target <- file.path(QS$paths$raw, "sentiment_gdelt_daily.csv")
n_total <- length(unlist(lapply(QS$universe, names)))

while (!file.exists(target) && Sys.time() < deadline) {
  ok <- tryCatch({ load_sentiment(refresh = TRUE); TRUE }, error = function(e) {
    message(format(Sys.time()), " GDELT error: ", substr(conditionMessage(e), 1, 120)); FALSE })
  n_done <- length(list.files(file.path(QS$paths$raw, "gdelt_cache")))
  message(format(Sys.time()), " cached tickers: ", n_done, "/", n_total)
  if (!ok) Sys.sleep(20 * 60)   # back off 20 minutes after a hard failure
}
if (!file.exists(target)) {
  message("sentiment download incomplete at deadline")
  quit(status = 1)
}
message("sentiment download complete")
