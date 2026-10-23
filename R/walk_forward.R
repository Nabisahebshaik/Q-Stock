# Chronological walk-forward evaluation.
#
# For each calendar month M (the test month):
#   train rows: feature date in [start(M) - train_months, start(M))
#               AND label_date < start(M)   <- embargo: no training label may be
#                                              revealed inside the test month
#   test rows : feature date in month M
# Scaling parameters and models are fit on the training rows only, then frozen.

month_start <- function(d) as.Date(format(d, "%Y-%m-01"))

add_months <- function(d, m) {
  lt <- as.POSIXlt(d); lt$mon <- lt$mon + m; as.Date(lt)
}

walk_forward_folds <- function(dates, train_months = QS$train_months) {
  months <- sort(unique(month_start(dates)))
  first_test <- add_months(min(months), train_months)
  months[months >= first_test]
}

wf_split <- function(data, m, train_months = QS$train_months, label_col = "label_date") {
  list(train = data[data$date >= add_months(m, -train_months) & data$date < m &
                      data[[label_col]] < m, ],
       test = data[data$date >= m & data$date < add_months(m, 1), ])
}

fit_predict <- function(model, train, test, cols, seed = 1) {
  mu <- colMeans(train[, cols, drop = FALSE])
  s <- apply(train[, cols, drop = FALSE], 2, sd); s[!is.finite(s) | s == 0] <- 1
  X  <- scale(as.matrix(train[, cols, drop = FALSE]), mu, s)
  Xt <- scale(as.matrix(test[, cols, drop = FALSE]), mu, s)
  y <- train$y_up
  if (model == "logit") {
    fit <- suppressWarnings(glm.fit(cbind(1, X), y, family = binomial()))
    b <- fit$coefficients; b[is.na(b)] <- 0
    as.numeric(plogis(cbind(1, Xt) %*% b))
  } else if (model == "rf") {
    d <- data.frame(X, y = factor(y, levels = c(0, 1)))
    fit <- ranger::ranger(y ~ ., data = d, num.trees = 300, min.node.size = 50,
                          probability = TRUE, seed = seed, num.threads = 4)
    predict(fit, data.frame(Xt))$predictions[, "1"]
  } else stop("unknown model ", model)
}

# OLS walk-forward for a continuous target (v2 realised-volatility forecasts).
# Same folds; the embargo uses `label_col` (e.g. the date of day t+5).
walk_forward_reg <- function(data, cols, target = "y_lrv5", label_col = "label_date_rv",
                             train_months = QS$train_months, min_train_rows = QS$min_train_rows) {
  data <- data[complete.cases(data[, c(cols, target, label_col)]), ]
  preds <- list()
  for (m in as.list(walk_forward_folds(data$date, train_months))) {
    sp <- wf_split(data, m, train_months, label_col)
    if (nrow(sp$train) < min_train_rows || nrow(sp$test) == 0) next
    X <- cbind(1, as.matrix(sp$train[, cols, drop = FALSE]))
    b <- qr.coef(qr(X), sp$train[[target]]); b[is.na(b)] <- 0
    p <- as.numeric(cbind(1, as.matrix(sp$test[, cols, drop = FALSE])) %*% b)
    preds[[length(preds) + 1]] <- data.frame(fold = format(m, "%Y-%m"), date = sp$test$date,
                                             ticker = sp$test$ticker, pred = p, y = sp$test[[target]])
  }
  out <- do.call(rbind, preds); rownames(out) <- NULL
  out
}

walk_forward <- function(data, cols, model = "logit", train_months = QS$train_months,
                         min_train_rows = QS$min_train_rows) {
  data <- data[complete.cases(data[, c(cols, "y_up", "label_date")]), ]
  preds <- list()
  for (m in as.list(walk_forward_folds(data$date, train_months))) {
    sp <- wf_split(data, m, train_months); train <- sp$train; test <- sp$test
    if (nrow(train) < min_train_rows || nrow(test) == 0) next
    p <- fit_predict(model, train, test, cols)
    preds[[length(preds) + 1]] <- data.frame(
      fold = format(m, "%Y-%m"), date = test$date, ticker = test$ticker, market = test$market,
      p_up = p, y_up = test$y_up, next_ret = test$next_ret,
      regime_hi = if ("regime_hi" %in% names(test)) test$regime_hi else NA_integer_)
  }
  out <- do.call(rbind, preds); rownames(out) <- NULL
  out
}
