# Structure the student's literature survey (Excel) for the novelty audit.
# Derived columns are keyword rules over the survey's own text (titles and
# "Proposed Solutions"), not a reading of the papers themselves.
#   Rscript scripts/09_literature_survey.R "C:/path/Literature_Survey.xlsx"

f <- commandArgs(trailingOnly = TRUE)[1]
raw <- readxl::read_excel(f, col_names = FALSE, col_types = "text")
hdr <- which(raw[[1]] == "S No")[1]
d <- as.data.frame(raw[(hdr + 1):nrow(raw), 1:7])
names(d) <- c("s_no", "title", "doi", "year", "proposed_solution", "limitation", "suggestion")
d <- d[!is.na(d$title) & d$title != "", ]
d$s_no <- as.integer(as.numeric(d$s_no)); d$year <- as.integer(as.numeric(d$year))
d$doi_ok <- grepl("^https?://doi\\.org/10\\.", d$doi)

txt <- tolower(paste(d$title, d$proposed_solution))
has <- function(p) grepl(p, txt)
d$family <- ifelse(has("transformer"), "Transformer",
            ifelse(has("lstm|rnn|gru|neural|deep"), "RNN/LSTM/DNN",
            ifelse(has("xgboost|random forest|ensemble"), "Tree/ensemble",
            ifelse(has("svm|svr|support vector"), "SVM/SVR",
            ifelse(has("regression|knn|arima"), "Linear/statistical", "unspecified")))))
d$uses_sentiment <- has("sentiment|news|vader|llm|annual report")
d$target <- ifelse(has("trend|direction|up or down|movement|classif"), "direction/trend",
            ifelse(has("price|closing|forecast"), "price level", "unclear"))
d$single_stock_noted <- grepl("only (one|tcs|reliance|hdfc|aapl|tesla)|single|one stock|three companies|four indian",
                              tolower(paste(d$limitation, d$proposed_solution)))
# "network" alone matches "neural network", so only graph/quantum-specific terms count.
d$graph_or_quantum <- has("graph|quantum|random walk|correlation network|stock network|market network")

out_csv <- "docs/literature_survey_structured.csv"
write.csv(d, out_csv, row.names = FALSE)
cat("papers:", nrow(d), " years:", paste(range(d$year, na.rm = TRUE), collapse = "-"),
    " DOI links:", sum(d$doi_ok), "\n")
print(table(d$family)); print(table(d$target))
cat("uses sentiment/text:", sum(d$uses_sentiment), "\n")
cat("graph/quantum/walk mentioned:", sum(d$graph_or_quantum), "\n")
cat("single-stock scope noted:", sum(d$single_stock_noted), "\n")
cat("rows without DOI link:", paste(d$s_no[!d$doi_ok], collapse = ", "), "\n")
