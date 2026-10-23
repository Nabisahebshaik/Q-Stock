# Export the live graph-HAR coefficients (fitted on the last 24 months of the research data)
# so the R API can run where the large curated data files are not available (cloud container).
#   Rscript scripts/26_export_ghar_coef.R   -> api/model/ghar_live_model.json
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
m <- lapply(c(NSE = "NSE", NASDAQ = "NASDAQ"), ghar_live_model)
stopifnot(!any(vapply(m, is.null, TRUE)))
out <- lapply(m, function(x) list(coef = as.list(x$coef), train_from = format(x$train_from), train_to = format(x$train_to), n = x$n))
dir.create("api/model", showWarnings = FALSE, recursive = TRUE)
writeLines(jsonlite::toJSON(out, auto_unbox = TRUE, digits = NA, pretty = TRUE), "api/model/ghar_live_model.json")
cat("wrote api/model/ghar_live_model.json\n")
