# Explainable forecasts. The live forecast is the graph-HAR regression
#   pred_i = b0 + sum_j b_j x_ij        (pred = log mean squared daily return, next 5 sessions)
# so its explanation is exact and needs no sampling: relative to the universe-average
# forecast of the same day, stock i's difference splits into one term per feature,
#   pred_i - mean(pred) = sum_j b_j (x_ij - mean_j x_j),
# which is the linear SHAP value with today's cross-section as the background
# (the research version, scripts/15_explainability.R, uses the training-period mean).
# On the volatility scale a term c_j multiplies the forecast by exp(c_j / 2).

EXPLAIN_FEATURES <- data.frame(
  feature = c("har_d", "har_w", "har_m", "gh_d", "gh_w", "gh_m"),
  label = c("Own volatility, last day", "Own volatility, last week", "Own volatility, last month",
            "Neighbours' volatility, last day", "Neighbours' volatility, last week", "Neighbours' volatility, last month"),
  group = c(rep("Own history (HAR)", 3), rep("Correlation-graph neighbours (GHAR)", 3)),
  stringsAsFactors = FALSE)

ann_vol <- function(lv) sqrt(exp(lv) * 252)   # log mean squared daily return -> annualised volatility

# f: the forecast data frame with attr "features" (ticker + GHAR_COLS); coef: named model coefficients.
explain_forecast <- function(f, coef, ticker) {
  X <- attr(f, "features")
  if (is.null(X) || !ticker %in% X$ticker) return(NULL)
  b <- stats::setNames(as.numeric(coef), c("(Intercept)", GHAR_COLS))
  M <- as.matrix(X[, GHAR_COLS]); mu <- colMeans(M)
  i <- match(ticker, X$ticker)
  contrib <- b[GHAR_COLS] * (M[i, ] - mu)
  pred <- f$pred_lrv5[match(ticker, f$ticker)]
  base <- unname(b[1] + sum(b[GHAR_COLS] * mu))             # = mean of the day's forecasts
  feats <- data.frame(EXPLAIN_FEATURES, value = unname(M[i, ]), value_vol = ann_vol(unname(M[i, ])),
                      mean = unname(mu), mean_vol = ann_vol(unname(mu)), coef = unname(b[GHAR_COLS]),
                      contribution = unname(contrib), vol_factor = exp(unname(contrib) / 2),
                      stringsAsFactors = FALSE)
  feats <- feats[order(-abs(feats$contribution)), ]
  grp <- stats::aggregate(contribution ~ group, feats, sum)
  list(ticker = ticker, as_of = format(f$as_of[match(ticker, f$ticker)]),
       pred_lrv5 = pred, vol5_ann = ann_vol(pred), baseline_lrv5 = base, baseline_vol5_ann = ann_vol(base),
       intercept = unname(b[1]), n_universe = nrow(X),
       check_sum = unname(sum(contrib) - (pred - base)),    # exactly 0 up to rounding
       rank = rank(-f$pred_lrv5)[match(ticker, f$ticker)],
       features = feats, groups = grp,
       summary = explain_text(ticker, pred, base, feats, grp))
}

explain_text <- function(ticker, pred, base, feats, grp) {
  pct <- function(x) sprintf("%.1f%%", 100 * x)
  dir <- if (pred >= base) "above" else "below"
  top <- feats[1, ]
  g <- grp[order(-abs(grp$contribution)), ][1, ]
  sprintf(paste0("%s: forecast 5-day volatility %s (annualised) vs %s for the average stock of its market today, ",
                 "%s the average. The largest single driver is %s (%s the forecast by a factor %.2f). ",
                 "By group, the %s inputs account for most of the gap."),
          short_label(ticker), pct(ann_vol(pred)), pct(ann_vol(base)), dir, tolower(top$label),
          if (top$contribution >= 0) "raising" else "lowering", top$vol_factor, g$group)
}
short_label <- function(tk) sub("\\.NS$", "", tk)
