# Start the Q-Stock API (and the built web UI, if web/dist exists). Run from the project root:
#   Rscript api/run_api.R [port]
# In a container: PORT and QSTOCK_HOST (e.g. 0.0.0.0) are read from the environment.
port <- as.integer(commandArgs(trailingOnly = TRUE)[1])
if (is.na(port)) port <- as.integer(Sys.getenv("PORT", "8000"))
host <- Sys.getenv("QSTOCK_HOST", "127.0.0.1")
options(qstock.root = normalizePath("."))
pr <- plumber::pr("api/plumber.R")
message("Q-Stock API on http://", host, ":", port)
plumber::pr_run(pr, host = host, port = port, docs = TRUE)
