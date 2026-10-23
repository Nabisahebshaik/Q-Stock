# v2 features: QSW node features on the daily market graph, and
# realised-volatility targets with HAR-RV baseline regressors.

# QSW features for one market and one omega. Same graph construction as v1
# (trailing correlation kNN graph, all information up to the close of t).
#   q_self     P[i, i]
#   q_mom      walk-weighted mean of neighbours' z-scored 5-day returns
#   q_ent      entropy of P[i, ]
#   q_volspill walk-weighted mean of neighbours' log 5-day realised variance
qsw_features_market <- function(prices_mk, omega, corr_window = QS$corr_window, k = QS$knn_k,
                                tau_max = QS$walk_time, graph = c("corr", "random"), seed = 1,
                                min_obs = 0.8) {
  graph <- match.arg(graph)
  if (graph == "random") set.seed(seed)
  R <- returns_wide(prices_mk)
  dates <- as.Date(rownames(R)); tick <- colnames(R)
  R0 <- R; R0[is.na(R0)] <- 0
  mom5 <- apply(R0, 2, function(x) as.numeric(stats::filter(x, rep(1, 5), sides = 1)))
  lrv5 <- log(apply(R0^2, 2, function(x) as.numeric(stats::filter(x, rep(1 / 5, 5), sides = 1))) + 1e-8)
  taus <- tau_max * seq_len(10) / 10
  rows <- vector("list", length(dates))
  for (t in seq(corr_window + 1, length(dates))) {
    win <- R[(t - corr_window + 1):t, , drop = FALSE]
    ok <- colMeans(!is.na(win)) >= min_obs & !is.na(R[t, ])
    if (sum(ok) < k + 2) next
    rho <- suppressWarnings(cor(win[, ok], use = "pairwise.complete.obs"))
    if (graph == "random") {
      rr <- matrix(runif(sum(ok)^2, -0.2, 0.9), sum(ok)); rr[lower.tri(rr)] <- t(rr)[lower.tri(rr)]
      dimnames(rr) <- dimnames(rho); rho <- rr
    }
    g <- knn_graph(rho, k)
    P <- qsw_distributions(g$w, omega, taus)
    P <- pmax(P, 0); P <- P / rowSums(P)
    sig <- mom5[t, ok]; sig <- (sig - mean(sig)) / sd(sig)
    off <- P; diag(off) <- 0; offs <- pmax(rowSums(off), 1e-12)
    rows[[t]] <- data.frame(
      date = dates[t], ticker = tick[ok],
      q_self = diag(P),
      q_mom = as.numeric(off %*% sig) / offs,
      q_ent = -rowSums(ifelse(P > 0, P * log(P), 0)),
      q_volspill = as.numeric(off %*% lrv5[t, ok]) / offs)
  }
  out <- do.call(rbind, rows); rownames(out) <- NULL
  out
}

omega_tag <- function(omega) sprintf("w%03d", round(omega * 100))

# GHAR-style regressors: correlation-weighted mean of one-hop neighbours' HAR terms
# on the same daily kNN graph (classical graph-HAR baseline).
ghar_features_market <- function(prices_mk, corr_window = QS$corr_window, k = QS$knn_k, min_obs = 0.8) {
  R <- returns_wide(prices_mk); dates <- as.Date(rownames(R)); tick <- colnames(R)
  R0 <- R; R0[is.na(R0)] <- 0; R2 <- R0^2
  roll <- function(w) apply(R2, 2, function(x) as.numeric(stats::filter(x, rep(1 / w, w), sides = 1)))
  H <- list(d = log(R2 + 1e-8), w = log(roll(5) + 1e-8), m = log(roll(22) + 1e-8))
  rows <- vector("list", length(dates))
  for (t in seq(corr_window + 1, length(dates))) {
    win <- R[(t - corr_window + 1):t, , drop = FALSE]
    ok <- colMeans(!is.na(win)) >= min_obs & !is.na(R[t, ])
    if (sum(ok) < k + 2) next
    g <- knn_graph(suppressWarnings(cor(win[, ok], use = "pairwise.complete.obs")), k)
    A <- g$w / rowSums(g$w)
    rows[[t]] <- data.frame(date = dates[t], ticker = tick[ok],
                            gh_d = as.numeric(A %*% H$d[t, ok]), gh_w = as.numeric(A %*% H$w[t, ok]),
                            gh_m = as.numeric(A %*% H$m[t, ok]))
  }
  do.call(rbind, rows)
}
GHAR_COLS <- c("har_d", "har_w", "har_m", "gh_d", "gh_w", "gh_m")

# HAR-RV regressors and the 5-day-ahead log realised-variance target.
#   har_d, har_w, har_m : log mean squared return over the last 1 / 5 / 22 days (up to t)
#   y_lrv5              : log mean squared return over days t+1 .. t+5
#   label_date_rv       : date of day t+5 (when the target is fully known)
build_vol_targets <- function(prices) {
  parts <- lapply(split(prices, prices$ticker), function(df) {
    df <- df[order(df$date), ]
    r <- c(NA, diff(log(df$close))); r2 <- r^2
    n <- length(r)
    fwd <- sapply(seq_len(n), function(i) if (i + 5 <= n) mean(r2[(i + 1):(i + 5)]) else NA)
    data.frame(ticker = df$ticker, date = df$date,
               har_d = log(r2 + 1e-8),
               har_w = log(trailing_mean(r2, 5) + 1e-8),
               har_m = log(trailing_mean(r2, 22) + 1e-8),
               y_lrv5 = log(fwd + 1e-8),
               label_date_rv = c(df$date[-(1:5)], rep(NA, 5))[seq_len(n)])
  })
  out <- do.call(rbind, parts); rownames(out) <- NULL
  out
}
HAR_COLS <- c("har_d", "har_w", "har_m")
