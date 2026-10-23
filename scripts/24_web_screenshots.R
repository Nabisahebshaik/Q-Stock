# Screenshot the React UI (served by the R API) in headless Edge, waiting in real time for
# live data and WebGL to render. The API must be running: Rscript api/run_api.R
#   Rscript scripts/24_web_screenshots.R [base_url] [wait_seconds] [theme]
args <- commandArgs(trailingOnly = TRUE)
base <- if (length(args) >= 1) args[1] else "http://127.0.0.1:8000/"
wait <- if (length(args) >= 2) as.numeric(args[2]) else 12
theme <- if (length(args) >= 3) args[3] else "dark"
edge <- "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
if (!nzchar(Sys.getenv("CHROMOTE_CHROME")) && file.exists(edge)) Sys.setenv(CHROMOTE_CHROME = edge)
suppressPackageStartupMessages(library(chromote))
dir.create("results/screenshots", showWarnings = FALSE, recursive = TRUE)
# A tall viewport from the start: resizing after load restarts chart animations mid-capture.
heights <- c(live = 2900, dial = 1700, research = 2000, pipeline = 1100)
for (pg in names(heights)) {
  b <- ChromoteSession$new(width = 1600, height = heights[[pg]])
  b$Page$navigate(paste0(base, "#", pg)); Sys.sleep(1)
  b$Runtime$evaluate(sprintf("try{localStorage.setItem('qstock-theme','%s')}catch(e){}", theme))
  b$Page$reload(); Sys.sleep(wait)
  out <- sprintf("results/screenshots/web_%s_%s.png", pg, theme)
  b$screenshot(out, selector = "#root", wait_ = TRUE)
  b$close()
  cat("wrote", out, "\n")
}
