qsw_test_graph <- function(n = 8, seed = 21) {
  set.seed(seed)
  r <- matrix(runif(n * n), n); r <- (r + t(r)) / 2
  knn_graph(r, 3)$w
}
taus <- seq(0.2, 2, by = 0.2)

test_that("QSW at omega = 0 equals the closed CTQW", {
  W <- qsw_test_graph()
  L <- diag(rowSums(W)) - W
  exact <- Reduce(`+`, lapply(taus, function(t) Mod(ctqw_propagator(L, t))^2)) / length(taus)
  expect_equal(qsw_distributions(W, 0, taus), exact, tolerance = 1e-6, ignore_attr = TRUE)
})

test_that("QSW at omega = 1 equals the classical heat kernel", {
  W <- qsw_test_graph()
  L <- diag(rowSums(W)) - W; e <- eigen(L, symmetric = TRUE)
  exact <- Reduce(`+`, lapply(taus, function(t) e$vectors %*% (exp(-t * e$values) * t(e$vectors)))) / length(taus)
  expect_equal(qsw_distributions(W, 1, taus), exact, tolerance = 1e-6, ignore_attr = TRUE)
})

test_that("QSW rows are probability distributions for intermediate omega", {
  W <- qsw_test_graph()
  for (om in c(0.1, 0.5, 0.9)) {
    P <- qsw_distributions(W, om, taus)
    expect_true(all(P > -1e-10), info = om)
    expect_equal(unname(rowSums(P)), rep(1, nrow(W)), tolerance = 1e-8, info = om)
  }
})

test_that("QSW preserves trace and Hermiticity, and decoheres (purity falls) for omega > 0", {
  W <- qsw_test_graph(); n <- nrow(W); d <- rowSums(W); H <- diag(d) - W
  R <- array(0 + 0i, c(n, n, 1)); R[1, 1, 1] <- 1
  for (k in 1:100) {   # RK4 to t = 2
    h <- 0.02
    k1 <- qsw_rhs(R, H, W, d, 0.5); k2 <- qsw_rhs(R + h / 2 * k1, H, W, d, 0.5)
    k3 <- qsw_rhs(R + h / 2 * k2, H, W, d, 0.5); k4 <- qsw_rhs(R + h * k3, H, W, d, 0.5)
    R <- R + h / 6 * (k1 + 2 * k2 + 2 * k3 + k4)
  }
  rho <- R[, , 1]
  expect_equal(qsw_trace(rho), 1, tolerance = 1e-10)
  expect_true(is_hermitian(rho, tol = 1e-10))
  expect_lt(qsw_purity(rho), 0.99)
  expect_true(all(eigen(rho, symmetric = TRUE, only.values = TRUE)$values > -1e-8))   # positive semidefinite
})
