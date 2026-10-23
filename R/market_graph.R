# Market-state graphs and walk-based node features.
#
# For each market and trading date t:
#   1. Correlations of daily log returns over the trailing `corr_window` days
#      ending at t (inclusive; all known at the close of t).
#   2. Symmetrised k-nearest-neighbour graph (highest correlations).
#      Edge weight = max(rho, 0.01) so weights stay positive.
#   3. Five walk/diffusion processes run on the SAME graph, each starting at
#      every node i, producing a distribution P[i, ] over nodes:
#        rw   classical random walk, averaged over steps 1..S
#        heat classical heat kernel exp(-tau L), averaged over tau in (0, T]
#        ppr  personalised PageRank (1 - a)(I - a T)^-1
#        dtqw Grover DTQW on the unweighted kNN graph, averaged over steps 1..S
#        ctqw CTQW |exp(-i tau L)|^2, averaged over tau in (0, T]
#   4. Identical node features from every P (so methods are directly comparable):
#        <m>_self  P[i, i]                   (return probability / localisation)
#        <m>_mom   P-weighted mean of the neighbours' z-scored 5-day returns
#        <m>_ent   Shannon entropy of P[i, ]

knn_graph <- function(rho, k) {
  n <- nrow(rho)
  a <- matrix(0, n, n)
  r <- rho; diag(r) <- -Inf; r[is.na(r)] <- -Inf
  for (i in seq_len(n)) a[i, order(r[i, ], decreasing = TRUE)[seq_len(min(k, n - 1))]] <- 1
  a <- pmax(a, t(a))
  w <- a * pmax(ifelse(is.na(rho), 0, rho), 0.01)
  list(adj = a, w = w)
}

walk_distributions <- function(adj, w, steps, tau_max, alpha, n_tau = 10) {
  n <- nrow(adj)
  taus <- tau_max * seq_len(n_tau) / n_tau
  deg <- rowSums(w)
  Tm <- w / deg
  L <- diag(deg) - w
  e <- eigen(L, symmetric = TRUE)
  V <- e$vectors; lam <- e$values

  # Classical random walk
  rw <- matrix(0, n, n); Pk <- diag(n)
  for (s in seq_len(steps)) { Pk <- Pk %*% Tm; rw <- rw + Pk }
  rw <- rw / steps

  heat <- matrix(0, n, n); ctqw <- matrix(0, n, n)
  for (tau in taus) {
    heat <- heat + V %*% (exp(-tau * lam) * t(V))
    U <- V %*% (exp(-1i * tau * lam) * t(V))
    ctqw <- ctqw + Mod(U)^2        # row i = start node i (U symmetric)
  }
  heat <- pmax(heat / n_tau, 0); ctqw <- ctqw / n_tau

  ppr <- (1 - alpha) * solve(diag(n) - alpha * Tm)

  # DTQW: evolve all start nodes at once (columns of Psi).
  g <- dtqw_graph_operator(adj)
  arcs <- g$arcs
  Psi <- sapply(seq_len(n), function(i) dtqw_graph_initial_state(arcs, i))
  from_f <- factor(arcs[, "from"], levels = seq_len(n))
  dtqw <- matrix(0, n, n)
  for (s in seq_len(steps)) {
    Psi <- g$U %*% Psi
    dtqw <- dtqw + t(apply(Mod(Psi)^2, 2, function(p) as.numeric(tapply(p, from_f, sum))))
  }
  dtqw <- dtqw / steps

  list(rw = rw, heat = heat, ppr = ppr, dtqw = dtqw, ctqw = ctqw)
}

node_features_from_P <- function(P, signal) {
  P <- P / rowSums(P)
  self <- diag(P)
  off <- P; diag(off) <- 0
  mom <- as.numeric(off %*% signal) / pmax(rowSums(off), 1e-12)
  ent <- -rowSums(ifelse(P > 0, P * log(P), 0))
  cbind(self = self, mom = mom, ent = ent)
}

# Wide matrix (dates x tickers) of log returns for one market.
returns_wide <- function(prices_mk) {
  prices_mk <- prices_mk[order(prices_mk$ticker, prices_mk$date), ]
  prices_mk$r <- ave(log(prices_mk$close), prices_mk$ticker, FUN = function(x) c(NA, diff(x)))
  dates <- sort(unique(prices_mk$date)); tick <- sort(unique(prices_mk$ticker))
  R <- matrix(NA_real_, length(dates), length(tick), dimnames = list(format(dates), tick))
  R[cbind(match(prices_mk$date, dates), match(prices_mk$ticker, tick))] <- prices_mk$r
  R
}

graph_features_market <- function(prices_mk, corr_window = QS$corr_window, k = QS$knn_k,
                                   steps = QS$walk_steps, tau_max = QS$walk_time,
                                   alpha = QS$ppr_alpha, min_obs = 0.8,
                                   graph = c("corr", "random"), seed = 1) {
  # graph = "random" is a control: same kNN construction but on random
  # "correlations", so any gain that survives it is not due to market structure.
  graph <- match.arg(graph)
  if (graph == "random") set.seed(seed)
  R <- returns_wide(prices_mk)
  dates <- as.Date(rownames(R)); tick <- colnames(R); n <- length(tick)
  R0 <- R; R0[is.na(R0)] <- 0
  mom5 <- apply(R0, 2, function(x) as.numeric(stats::filter(x, rep(1, 5), sides = 1)))
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
    sig <- mom5[t, ok]; sig <- (sig - mean(sig)) / sd(sig)
    Ps <- walk_distributions(g$adj, g$w, steps, tau_max, alpha)
    f <- do.call(cbind, lapply(names(Ps), function(m) {
      x <- node_features_from_P(Ps[[m]], sig); colnames(x) <- paste0(m, "_", colnames(x)); x
    }))
    rows[[t]] <- data.frame(date = dates[t], ticker = tick[ok], f, check.names = FALSE)
  }
  out <- do.call(rbind, rows); rownames(out) <- NULL
  out
}
