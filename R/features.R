# Leakage-safe classical features and labels.
#
# Convention: a row dated t holds only information available at the close of
# day t. The label for that row is the direction of the return from t to t+1.
# Features never use any value later than t.

# A missing value makes only the windows that contain it NA (a plain cumsum
# would propagate one NA to every later value).
trailing_mean <- function(x, k) {
  out <- rep(NA_real_, length(x))
  if (length(x) >= k) {
    miss <- is.na(x)
    cs <- cumsum(c(0, ifelse(miss, 0, x)))
    cm <- cumsum(c(0, miss))
    idx <- k:length(x)
    s <- (cs[idx + 1] - cs[idx - k + 1]) / k
    s[(cm[idx + 1] - cm[idx - k + 1]) > 0] <- NA
    out[idx] <- s
  }
  out
}

trailing_sd <- function(x, k) {
  m <- trailing_mean(x, k)
  m2 <- trailing_mean(x^2, k)
  sqrt(pmax(m2 - m^2, 0) * k / (k - 1))
}

build_features_one <- function(df) {
  df <- df[order(df$date), ]
  r <- c(NA, diff(log(df$close)))
  r0 <- ifelse(is.na(r), 0, r)
  df$ret_1  <- r
  df$ret_5  <- trailing_mean(r0, 5) * 5
  df$ret_20 <- trailing_mean(r0, 20) * 20
  df$vol_10 <- trailing_sd(r0, 10)
  df$vol_20 <- trailing_sd(r0, 20)
  df$range  <- log(df$high / df$low)
  df$log_vol_z <- (log(df$volume) - trailing_mean(log(df$volume), 20)) /
    trailing_sd(log(df$volume), 20)
  # Label: next-day direction. This is the ONLY place a future value is used.
  df$next_ret <- c(r[-1], NA)
  df$label_date <- c(df$date[-1], NA)   # date on which the label becomes known
  df$y_up <- as.integer(df$next_ret > 0)
  df[-1, ]   # first row has no return
}

FEATURE_COLS <- c("ret_1", "ret_5", "ret_20", "vol_10", "vol_20", "range", "log_vol_z")

build_features <- function(prices) {
  parts <- lapply(split(prices, prices$ticker), build_features_one)
  out <- do.call(rbind, parts)
  rownames(out) <- NULL
  out[complete.cases(out[, c(FEATURE_COLS, "y_up")]), ]
}
