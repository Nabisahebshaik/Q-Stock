# Stage 4: scalability of the classical quantum-walk simulations.
# Runtime and R-heap allocation vs graph size N (random symmetrised kNN graphs, k = 4).
# Run from the project root:  Rscript scripts/07_scalability.R

for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
ensure_dirs()
set.seed(7)

random_knn <- function(n, k = 4) {
  r <- matrix(runif(n * n), n); r <- (r + t(r)) / 2
  knn_graph(r, k)
}

steps <- 10; taus <- seq(0.2, 2, by = 0.2)

dtqw_all_starts <- function(g, n, sparse) {
  op <- if (sparse) dtqw_graph_operator_sparse(g$adj) else dtqw_graph_operator(g$adj)
  Psi <- sapply(seq_len(n), function(i) dtqw_graph_initial_state(op$arcs, i))
  if (sparse) {
    # Matrix has no complex sparse type: evolve real and imaginary parts separately
    # (U is real for the Grover walk, so U(a + ib) = Ua + i Ub).
    re <- Re(Psi); im <- Im(Psi)
    for (s in seq_len(steps)) { re <- as.matrix(op$U %*% re); im <- as.matrix(op$U %*% im) }
    invisible(re^2 + im^2)
  } else {
    for (s in seq_len(steps)) Psi <- op$U %*% Psi
    invisible(Mod(Psi)^2)
  }
}

ctqw_all_starts <- function(g) {
  L <- diag(rowSums(g$w)) - g$w
  e <- eigen(L, symmetric = TRUE)
  P <- 0
  for (tau in taus) P <- P + Mod(e$vectors %*% (exp(-1i * tau * e$values) * t(e$vectors)))^2
  invisible(P / length(taus))
}

rw_all_starts <- function(g) {
  Tm <- g$w / rowSums(g$w); Pk <- diag(nrow(Tm)); acc <- 0
  for (s in seq_len(steps)) { Pk <- Pk %*% Tm; acc <- acc + Pk }
  invisible(acc / steps)
}

rows <- list()
for (n in c(25, 50, 100, 200, 400, 800, 1600)) {
  g <- random_knn(n)
  n_arcs <- sum(g$adj)
  cases <- list(
    dtqw_sparse = function() dtqw_all_starts(g, n, TRUE),
    ctqw_eigen = function() ctqw_all_starts(g),
    classical_rw = function() rw_all_starts(g))
  if (n <= 400) cases$dtqw_dense <- function() dtqw_all_starts(g, n, FALSE)
  for (nm in names(cases)) {
    b <- bench::mark(cases[[nm]](), iterations = if (n >= 800) 1 else 3, check = FALSE,
                     filter_gc = FALSE, memory = TRUE)
    rows[[length(rows) + 1]] <- data.frame(n_nodes = n, n_arcs = n_arcs, method = nm,
                                           median_seconds = as.numeric(b$median),
                                           mem_alloc_mb = as.numeric(b$mem_alloc) / 2^20)
    print(tail(rows, 1)[[1]])
  }
}
sc <- do.call(rbind, rows)
write.csv(sc, file.path(QS$paths$tables, "qw_scalability.csv"), row.names = FALSE)

# Log-log slope (empirical complexity exponent) for N >= 100.
slopes <- do.call(rbind, lapply(split(sc, sc$method), function(d) {
  d <- d[d$n_nodes >= 100, ]
  data.frame(method = d$method[1], time_exponent = unname(coef(lm(log(median_seconds) ~ log(n_nodes), d))[2]))
}))
print(slopes)
write.csv(slopes, file.path(QS$paths$tables, "qw_scalability_exponents.csv"), row.names = FALSE)
writeLines(c(capture.output(sessionInfo()), "", paste("BLAS:", extSoftVersion()[["BLAS"]]),
             paste("La_library:", La_library())), file.path(QS$paths$results, "scalability_sessionInfo.txt"))
