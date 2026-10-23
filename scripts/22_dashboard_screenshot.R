# Screenshot dashboard tabs in a real (headless) browser, waiting in real time for the
# Shiny server to push its outputs. The dashboard must already be running:
#   Rscript -e "shiny::runApp('app', port = 8050)"
#   Rscript scripts/22_dashboard_screenshot.R ["Live market"] [wait_seconds]
args <- commandArgs(trailingOnly = TRUE)
tab <- if (length(args) >= 1) args[1] else "Live market"
wait <- if (length(args) >= 2) as.numeric(args[2]) else 20
edge <- "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
if (!nzchar(Sys.getenv("CHROMOTE_CHROME")) && file.exists(edge)) Sys.setenv(CHROMOTE_CHROME = edge)
suppressPackageStartupMessages(library(chromote))
dir.create("results/screenshots", showWarnings = FALSE, recursive = TRUE)
b <- ChromoteSession$new(width = 1500, height = 2300)
b$Page$navigate(paste0("http://127.0.0.1:8050/?tab=", utils::URLencode(tab, reserved = TRUE)))
Sys.sleep(wait)
out <- file.path("results/screenshots", paste0(gsub("[^a-z0-9]+", "_", tolower(tab)), "_tab.png"))
b$screenshot(out, selector = "body", wait_ = TRUE)
b$close()
cat("wrote", out, "\n")
