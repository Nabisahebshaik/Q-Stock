random_weighted_graph <- function(n, p = 0.5, seed = 7) {
  set.seed(seed)
  w <- matrix(runif(n * n) * (runif(n * n) < p), n)
  w[lower.tri(w)] <- 0
  w + t(w)
}

test_that("CTQW Hamiltonians are Hermitian with dimension N x N", {
  adj <- random_weighted_graph(10)
  for (type in c("laplacian", "adjacency")) {
    H <- ctqw_hamiltonian(adj, type)
    expect_equal(dim(H), c(10, 10))
    expect_true(is_hermitian(H))
  }
  expect_equal(rowSums(ctqw_hamiltonian(adj, "laplacian")), rep(0, 10), tolerance = 1e-12)
})

test_that("CTQW rejects non-symmetric or negative-weight graphs", {
  expect_error(ctqw_hamiltonian(matrix(c(0, 1, 0, 0), 2)), "symmetric")
  expect_error(ctqw_hamiltonian(matrix(c(0, -1, -1, 0), 2)), "non-negative")
})

test_that("CTQW propagator is unitary and states stay normalized", {
  H <- ctqw_hamiltonian(random_weighted_graph(12))
  U <- ctqw_propagator(H, t = 2.5, gamma = 0.7)
  expect_true(is_unitary(U))
  times <- seq(0, 10, by = 0.5)
  states <- ctqw_evolve(H, ctqw_initial_state(12, 3), times, gamma = 0.7)
  expect_equal(dim(states), c(length(times), 12))
  expect_equal(rowSums(Mod(states)^2), rep(1, length(times)), tolerance = 1e-10)
  # Eigen-based evolution agrees with the explicit propagator.
  expect_equal(states[times == 2.5, ], as.vector(U %*% ctqw_initial_state(12, 3)),
               tolerance = 1e-10)
})

test_that("CTQW at t = 0 is the identity", {
  H <- ctqw_hamiltonian(random_weighted_graph(5))
  expect_equal(ctqw_propagator(H, 0), diag(5) + 0i, tolerance = 1e-12)
})
