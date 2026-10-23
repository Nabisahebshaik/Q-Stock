# Discrete-time quantum walk (DTQW) simulation in base R.
#
# This is a CLASSICAL simulation of a quantum walk: state vectors are evolved
# with dense complex matrices on an ordinary CPU. Nothing here runs on quantum
# hardware.
#
# Two walk models are provided:
#   1. Coined Hadamard walk on an N-cycle (textbook model, used for validation).
#   2. Arc-based Grover walk on an arbitrary undirected graph (flip-flop shift),
#      which Stage 2 will apply to market-state graphs.

# ---------------------------------------------------------------------------
# 1. Coined walk on an N-cycle
#    Basis ordering: index = (coin - 1) * N + position, coin in {1 = left, 2 = right}
# ---------------------------------------------------------------------------

hadamard_coin <- function() {
  matrix(c(1, 1, 1, -1), nrow = 2) / sqrt(2)
}

dtqw_cycle_operator <- function(n, coin = hadamard_coin()) {
  stopifnot(n >= 3, all(dim(coin) == c(2, 2)))
  dim_total <- 2 * n
  shift <- matrix(0, dim_total, dim_total)
  for (x in seq_len(n)) {
    left  <- ((x - 2) %% n) + 1
    right <- (x %% n) + 1
    shift[left, x] <- 1               # coin 1 moves left
    shift[n + right, n + x] <- 1      # coin 2 moves right
  }
  coin_full <- kronecker(coin, diag(n))
  shift %*% coin_full
}

dtqw_cycle_initial_state <- function(n, start = 1,
                                     coin_state = c(1, 1i) / sqrt(2)) {
  psi <- complex(2 * n)
  psi[start] <- coin_state[1]
  psi[n + start] <- coin_state[2]
  psi
}

dtqw_cycle_position_probs <- function(psi, n) {
  p <- Mod(psi)^2
  p[seq_len(n)] + p[n + seq_len(n)]
}

# ---------------------------------------------------------------------------
# 2. Arc-based Grover walk on an undirected graph
#    State space = directed arcs (u -> v) for every edge {u, v}: dimension 2|E|.
#    Coin  : Grover diffusion 2/d * J - I over the out-arcs of each vertex.
#    Shift : flip-flop, |u -> v>  maps to  |v -> u>.
# ---------------------------------------------------------------------------

graph_arcs <- function(adj) {
  stopifnot(is.matrix(adj), nrow(adj) == ncol(adj), isSymmetric(unname(adj)))
  idx <- which(adj != 0 & upper.tri(adj), arr.ind = TRUE)
  if (nrow(idx) == 0) stop("graph has no edges")
  arcs <- rbind(cbind(from = idx[, 1], to = idx[, 2]),
                cbind(from = idx[, 2], to = idx[, 1]))
  arcs[order(arcs[, "from"], arcs[, "to"]), , drop = FALSE]
}

dtqw_graph_operator <- function(adj) {
  arcs <- graph_arcs(adj)
  m <- nrow(arcs)
  if (any(rowSums(adj != 0) == 0)) stop("graph has isolated vertices")

  coin <- matrix(0, m, m)
  for (v in unique(arcs[, "from"])) {
    out <- which(arcs[, "from"] == v)
    d <- length(out)
    coin[out, out] <- 2 / d - diag(d)
  }

  key <- paste(arcs[, "from"], arcs[, "to"])
  rev_key <- paste(arcs[, "to"], arcs[, "from"])
  shift <- matrix(0, m, m)
  shift[cbind(match(rev_key, key), seq_len(m))] <- 1

  list(U = shift %*% coin, arcs = arcs)
}

# Same operator as dtqw_graph_operator(), built as a sparse matrix (Matrix
# package). nnz = sum(deg^2) instead of (2|E|)^2, which matters for large graphs.
dtqw_graph_operator_sparse <- function(adj) {
  arcs <- graph_arcs(adj)
  m <- nrow(arcs)
  if (any(rowSums(adj != 0) == 0)) stop("graph has isolated vertices")
  by_v <- split(seq_len(m), arcs[, "from"])
  ii <- unlist(lapply(by_v, function(o) rep(o, times = length(o))))
  jj <- unlist(lapply(by_v, function(o) rep(o, each = length(o))))
  xx <- unlist(lapply(by_v, function(o) {
    d <- length(o); as.vector(2 / d - diag(d))
  }))
  coin <- Matrix::sparseMatrix(i = ii, j = jj, x = xx, dims = c(m, m))
  key <- paste(arcs[, "from"], arcs[, "to"])
  shift <- Matrix::sparseMatrix(i = match(paste(arcs[, "to"], arcs[, "from"]), key),
                                j = seq_len(m), x = 1, dims = c(m, m))
  list(U = shift %*% coin, arcs = arcs)
}

dtqw_graph_initial_state <- function(arcs, start) {
  out <- which(arcs[, "from"] == start)
  psi <- complex(nrow(arcs))
  psi[out] <- 1 / sqrt(length(out))
  psi
}

# Vertex probability = total probability on arcs leaving that vertex.
dtqw_graph_vertex_probs <- function(psi, arcs, n_vertices) {
  p <- Mod(psi)^2
  as.numeric(tapply(p, factor(arcs[, "from"], levels = seq_len(n_vertices)), sum))
}

# ---------------------------------------------------------------------------
# Generic evolution: returns a (steps + 1) x dim complex matrix of states.
# ---------------------------------------------------------------------------

dtqw_evolve <- function(U, psi0, steps) {
  stopifnot(nrow(U) == length(psi0), steps >= 0)
  states <- matrix(0 + 0i, steps + 1, length(psi0))
  states[1, ] <- psi0
  psi <- psi0
  for (t in seq_len(steps)) {
    psi <- as.vector(U %*% psi)
    states[t + 1, ] <- psi
  }
  states
}

is_unitary <- function(U, tol = 1e-10) {
  max(Mod(Conj(t(U)) %*% U - diag(nrow(U)))) < tol
}
