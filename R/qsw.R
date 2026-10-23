# Quantum stochastic walk (QSW): Lindblad master equation on a weighted graph.
#
#   d rho / dt = -(1 - w) i [H, rho]
#                + w * sum_{i != j} g_ij ( L_ij rho L_ij^+ - 1/2 {L_ij^+ L_ij, rho} )
#
# with H = graph Laplacian, L_ij = |i><j|, g_ij = W_ij (edge weights).
#   w = 0 : closed continuous-time quantum walk  U(t) = exp(-i L t)
#   w = 1 : classical continuous-time random walk p(t) = exp(-L t) p(0)
# CLASSICAL simulation (RK4 on density matrices); no quantum hardware.
#
# For the dissipator, with p = diag(rho) and d = rowSums(W):
#   sum_ij g_ij L_ij rho L_ij^+ = diag(W %*% p)
#   sum_ij g_ij L_ij^+ L_ij     = diag(d)

# Right-hand side for S start states at once. R is an N x N x S complex array.
qsw_rhs <- function(R, H, W, d, omega) {
  n <- dim(R)[1]; S <- dim(R)[3]
  Rm <- matrix(R, n)                                   # N x (N*S): [rho_1 | ... | rho_S]
  HR <- array(H %*% Rm, c(n, n, S))                    # H rho_s
  RH <- Conj(aperm(HR, c(2, 1, 3)))                    # rho_s H = (H rho_s)^+  (H, rho Hermitian)
  out <- -(1 - omega) * 1i * (HR - RH)
  if (omega > 0) {
    idx <- cbind(rep(seq_len(n), S), rep(seq_len(n), S), rep(seq_len(S), each = n))
    P <- matrix(Re(R[idx]), n)                         # populations, N x S
    jump <- W %*% P                                    # N x S
    anti <- sweep(R, 1, d, `*`) + sweep(R, 2, d, `*`)  # D rho + rho D
    diss <- -0.5 * anti
    diss[idx] <- diss[idx] + as.vector(jump)
    out <- out + omega * diss
  }
  out
}

# Time-averaged node distributions for walks started at every node.
# Returns an N x N matrix, row i = start node i, averaged over taus.
# exact_limits = TRUE uses the closed forms at the two ends of the dial (omega = 0: closed CTQW,
# |exp(-iHt)|^2; omega = 1: classical heat kernel exp(-Lt)) instead of integrating. The unit tests
# check that the integrator reproduces both to 1e-6. Research scripts keep the default (integrator)
# so published results are reproduced exactly; the live API uses the closed forms for speed.
qsw_distributions <- function(W, omega, taus = seq(0.2, 2, by = 0.2), h = 0.02, exact_limits = FALSE) {
  stopifnot(isSymmetric(unname(W)), all(W >= 0), omega >= 0, omega <= 1)
  n <- nrow(W); d <- rowSums(W); H <- diag(d) - W
  if (exact_limits && omega %in% c(0, 1)) {
    e <- eigen(H, symmetric = TRUE); V <- e$vectors
    one <- if (omega == 0) function(t) Mod(V %*% (exp(-1i * t * e$values) * t(V)))^2
           else function(t) V %*% (exp(-t * e$values) * t(V))
    return(Reduce(`+`, lapply(taus, one)) / length(taus))
  }
  R <- array(0 + 0i, c(n, n, n))
  for (s in seq_len(n)) R[s, s, s] <- 1
  idx <- cbind(rep(seq_len(n), n), rep(seq_len(n), n), rep(seq_len(n), each = n))
  marks <- round(taus / h)
  acc <- matrix(0, n, n); t_step <- 0
  for (k in seq_len(max(marks))) {
    k1 <- qsw_rhs(R, H, W, d, omega)
    k2 <- qsw_rhs(R + h / 2 * k1, H, W, d, omega)
    k3 <- qsw_rhs(R + h / 2 * k2, H, W, d, omega)
    k4 <- qsw_rhs(R + h * k3, H, W, d, omega)
    R <- R + h / 6 * (k1 + 2 * k2 + 2 * k3 + k4)
    if (k %in% marks) acc <- acc + t(matrix(Re(R[idx]), n))   # row = start node
  }
  acc / length(marks)
}

# Diagnostics on a single density matrix.
qsw_trace <- function(rho) Re(sum(diag(rho)))
qsw_purity <- function(rho) Re(sum(diag(rho %*% rho)))
