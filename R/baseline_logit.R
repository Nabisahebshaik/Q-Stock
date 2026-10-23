# Classical logistic-regression baseline with a single chronological split.
# (Walk-forward evaluation is Stage 2.)

chrono_split <- function(df, train_frac = 0.7) {
  dates <- sort(unique(df$date))
  cutoff <- dates[floor(length(dates) * train_frac)]
  list(train = df[df$date <= cutoff, ], test = df[df$date > cutoff, ], cutoff = cutoff)
}

standardize_fit <- function(train, cols) {
  list(mu = colMeans(train[, cols]), sd = apply(train[, cols], 2, sd))
}

standardize_apply <- function(df, scaler, cols) {
  df[, cols] <- sweep(sweep(as.matrix(df[, cols]), 2, scaler$mu), 2, scaler$sd, "/")
  df
}

classification_metrics <- function(y, pred) {
  tp <- sum(pred == 1 & y == 1); fp <- sum(pred == 1 & y == 0)
  fn <- sum(pred == 0 & y == 1)
  precision <- if (tp + fp == 0) NA else tp / (tp + fp)
  recall <- if (tp + fn == 0) NA else tp / (tp + fn)
  f1 <- if (is.na(precision) || is.na(recall) || precision + recall == 0) NA else
    2 * precision * recall / (precision + recall)
  c(n = length(y), accuracy = mean(pred == y), precision = precision,
    recall = recall, f1 = f1, base_rate_up = mean(y))
}

fit_logit_baseline <- function(features, cols = FEATURE_COLS, train_frac = 0.7) {
  sp <- chrono_split(features, train_frac)
  # Scaler is fit on the training window only.
  scaler <- standardize_fit(sp$train, cols)
  train <- standardize_apply(sp$train, scaler, cols)
  test <- standardize_apply(sp$test, scaler, cols)
  fml <- as.formula(paste("y_up ~", paste(cols, collapse = " + ")))
  model <- glm(fml, data = train, family = binomial())
  p_test <- predict(model, newdata = test, type = "response")
  list(model = model, cutoff = sp$cutoff,
       train_metrics = classification_metrics(train$y_up, as.integer(fitted(model) > 0.5)),
       test_metrics = classification_metrics(test$y_up, as.integer(p_test > 0.5)))
}
