# Start the Q-Stock API (and the built web UI, if web/dist exists). Run from the project root:
#   Rscript api/run_api.R [port]
port <- as.integer(commandArgs(trailingOnly = TRUE)[1]); if (is.na(port)) port <- 8000L
options(qstock.root = normalizePath("."))
pr <- plumber::pr("api/plumber.R")
message("Q-Stock API on http://127.0.0.1:", port)
plumber::pr_run(pr, host = "127.0.0.1", port = port, docs = TRUE)
