# Start the Q-Stock API (and the built web UI, if web/dist exists). Run from the project root:
#   Rscript api/run_api.R [port]
# In a container: PORT and QSTOCK_HOST (e.g. 0.0.0.0) are read from the environment.
# Kotak Neo (optional, docs/operations/KOTAK_NEO.md): with KOTAK_* set in .Renviron but no
# KOTAK_TOTP_SECRET, the 6-digit code from the authenticator app is asked for here.
port <- as.integer(commandArgs(trailingOnly = TRUE)[1])
if (is.na(port)) port <- as.integer(Sys.getenv("PORT", "8000"))
host <- Sys.getenv("QSTOCK_HOST", "127.0.0.1")
options(qstock.root = normalizePath("."))
kotak_vars <- Sys.getenv(c("KOTAK_ACCESS_TOKEN", "KOTAK_MOBILE", "KOTAK_UCC", "KOTAK_MPIN"))
if (all(nzchar(kotak_vars)) && !nzchar(Sys.getenv("KOTAK_TOTP_SECRET")) && isatty(stdin())) {
  cat("Kotak Neo: enter the 6-digit code from your authenticator app (Enter to skip): ")
  code <- trimws(readLines(file("stdin"), n = 1))
  if (grepl("^[0-9]{6}$", code)) options(qstock.kotak_totp = code) else message("Kotak Neo skipped: NSE live data from Yahoo")
}
pr <- plumber::pr("api/plumber.R")
message("Q-Stock API on http://", host, ":", port)
plumber::pr_run(pr, host = host, port = port, docs = TRUE)
