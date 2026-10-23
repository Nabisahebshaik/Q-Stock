# Export a static snapshot of the R API for hosting the web UI without an R server
# (e.g. on Vercel, which cannot run R). Starts the API, calls every endpoint the UI uses,
# and writes the JSON responses to web/public/data/. The UI built with `--mode snapshot`
# reads these files and labels every page "snapshot of <time>".
#   Rscript scripts/25_export_snapshot.R
# Grid: omega in steps of 0.05; graph window fixed at 120 one-minute returns; dial on the
# latest date. These are the only settings the snapshot UI offers.
port <- 8766L
root <- normalizePath(".")
out <- file.path(root, "web", "public", "data")
unlink(out, recursive = TRUE); dir.create(out, recursive = TRUE)
srv <- callr::r_bg(function(root, port) {
  setwd(root); options(qstock.root = root)
  plumber::pr_run(plumber::pr("api/plumber.R"), host = "127.0.0.1", port = port, docs = FALSE)
}, args = list(root = root, port = port))
on.exit(srv$kill(), add = TRUE)
base <- sprintf("http://127.0.0.1:%d", port)
for (i in 1:120) { ok <- tryCatch(httr::status_code(httr::GET(paste0(base, "/api/status"))) == 200, error = function(e) FALSE); if (ok) break; Sys.sleep(1) }
if (!ok) stop("API did not start: ", srv$read_all_error())

n_files <- 0; bytes <- 0
save <- function(path, file) {
  r <- httr::GET(paste0(base, path), httr::timeout(300))
  if (httr::status_code(r) != 200) stop(path, ": HTTP ", httr::status_code(r))
  txt <- httr::content(r, "text", encoding = "UTF-8")
  writeLines(txt, file.path(out, file), useBytes = TRUE)
  n_files <<- n_files + 1; bytes <<- bytes + nchar(txt, type = "bytes")
  invisible(jsonlite::fromJSON(txt, simplifyVector = FALSE))
}
tag <- function(w) sprintf("%03d", round(w * 100))
omegas <- seq(0, 1, by = 0.05)

st <- save("/api/status", "status.json")
for (s in st) {
  mk <- s$market
  save(paste0("/api/live/", mk), sprintf("live_%s.json", mk))
  for (tk in vapply(s$tickers, `[[`, "", "ticker")) save(sprintf("/api/candles/%s/%s", mk, utils::URLencode(tk, reserved = TRUE)), sprintf("candles_%s_%s.json", mk, tk))
  for (w in omegas) {
    save(sprintf("/api/graph/%s?omega=%.2f&look=120", mk, w), sprintf("graph_%s_%s.json", mk, tag(w)))
    save(sprintf("/api/dial?market=%s&omega=%.2f", mk, w), sprintf("dial_%s_%s.json", mk, tag(w)))
  }
  save(paste0("/api/forecast/", mk), sprintf("forecast_%s.json", mk))
  message(format(Sys.time(), "%H:%M:%S"), " ", mk, " exported")
}
save("/api/results", "results.json")
writeLines(jsonlite::toJSON(list(snapshot_at = as.numeric(Sys.time()),
                                 snapshot_iso = format(Sys.time(), "%Y-%m-%d %H:%M %Z"),
                                 omega_step = 0.05, look = 120L), auto_unbox = TRUE), file.path(out, "meta.json"))
cat(sprintf("wrote %d files (%.1f MB) to %s\n", n_files + 1, bytes / 1e6, out))
