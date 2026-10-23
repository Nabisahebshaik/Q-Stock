# Run from the project root:  Rscript tests/run_tests.R
library(testthat)
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
res <- test_dir("tests/testthat", reporter = "summary", stop_on_failure = FALSE)
df <- as.data.frame(res)
cat(sprintf("\nTOTAL: %d test blocks, %d expectations, %d failed, %d errored, %d skipped\n",
            nrow(df), sum(df$nb), sum(df$failed), sum(df$error), sum(df$skipped)))
quit(status = as.integer(any(df$failed > 0 | df$error)))
