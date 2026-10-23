# Continuous-time quantum walk (CTQW) simulation in base R.
#
# CLASSICAL simulation: U(t) = exp(-i * gamma * H * t) is computed by
# eigendecomposition on a CPU. No quantum hardware is involved.
#
# The Hamiltonian is built from a weighted undirected graph, either the
# adjacency matrix A or the combinatorial Laplacian L = D - A.

ctqw_hamiltonian <- function(adj, type = c("laplacian", "adjacency")) {
  type <- match.arg(type)
  stopifnot(is.matrix(adj), nrow(adj) == ncol(adj))
  if (!isSymmetric(unname(adj))) stop("adjacency must be symmetric for a Hermitian H")
  if (any(adj < 0)) stop("edge weights must be non-negative")
  if (type == "adjacency") adj else diag(rowSums(adj)) - adj
}

is_hermitian <- function(H, tol = 1e-10) {
  max(Mod(H - Conj(t(H)))) < tol
}

ctqw_propagator <- function(H, t, gamma = 1) {
  if (!is_hermitian(H)) stop("H is not Hermitian")
  e <- eigen(H, symmetric = TRUE)
  phases <- exp(-1i * gamma * e$values * t)
  e$vectors %*% (phases * t(Conj(e$vectors)))
}

ctqw_initial_state <- function(n, start = 1) {
  psi <- complex(n)
  psi[start] <- 1
  psi
}

# Returns a length(times) x n complex matrix of states psi(t).
ctqw_evolve <- function(H, psi0, times, gamma = 1) {
  stopifnot(nrow(H) == length(psi0))
  e <- eigen(H, symmetric = TRUE)
  coeffs <- as.vector(t(Conj(e$vectors)) %*% psi0)
  states <- matrix(0 + 0i, length(times), length(psi0))
  for (k in seq_along(times)) {
    states[k, ] <- e$vectors %*% (exp(-1i * gamma * e$values * times[k]) * coeffs)
  }
  states
}

ctqw_probs <- function(psi) Mod(psi)^2
