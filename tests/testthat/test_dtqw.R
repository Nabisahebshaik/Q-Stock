test_that("cycle DTQW operator has dimension 2N and is unitary", {
  for (n in c(3, 8, 21)) {
    U <- dtqw_cycle_operator(n)
    expect_equal(dim(U), c(2 * n, 2 * n))
    expect_true(is_unitary(U))
  }
})

test_that("cycle DTQW preserves state normalization", {
  n <- 15
  states <- dtqw_evolve(dtqw_cycle_operator(n), dtqw_cycle_initial_state(n, 8), 40)
  expect_equal(dim(states), c(41, 2 * n))
  norms <- rowSums(Mod(states)^2)
  expect_equal(norms, rep(1, 41), tolerance = 1e-10)
  probs <- dtqw_cycle_position_probs(states[41, ], n)
  expect_length(probs, n)
  expect_equal(sum(probs), 1, tolerance = 1e-10)
})

test_that("Hadamard walk spreads ballistically, unlike a classical random walk", {
  # On a large cycle the quantum walk std grows ~linearly in t, the classical one ~sqrt(t).
  n <- 201; start <- 101; steps <- 60
  states <- dtqw_evolve(dtqw_cycle_operator(n), dtqw_cycle_initial_state(n, start), steps)
  p <- dtqw_cycle_position_probs(states[steps + 1, ], n)
  x <- seq_len(n) - start
  sd_quantum <- sqrt(sum(p * x^2) - sum(p * x)^2)
  expect_gt(sd_quantum, 2 * sqrt(steps))
})

test_that("Grover graph walk is unitary with dimension 2|E| and preserves norm", {
  set.seed(1)
  adj <- matrix(0, 6, 6)
  edges <- rbind(c(1, 2), c(2, 3), c(3, 4), c(4, 5), c(5, 6), c(6, 1), c(1, 4), c(2, 5))
  adj[edges] <- 1; adj[edges[, 2:1]] <- 1
  w <- dtqw_graph_operator(adj)
  expect_equal(dim(w$U), c(2 * nrow(edges), 2 * nrow(edges)))
  expect_true(is_unitary(w$U))
  states <- dtqw_evolve(w$U, dtqw_graph_initial_state(w$arcs, 1), 25)
  expect_equal(rowSums(Mod(states)^2), rep(1, 26), tolerance = 1e-10)
  expect_equal(sum(dtqw_graph_vertex_probs(states[26, ], w$arcs, 6)), 1, tolerance = 1e-10)
})

test_that("sparse Grover operator equals the dense one", {
  set.seed(2)
  n <- 12; adj <- matrix(0, n, n)
  for (i in 1:n) { j <- sample(setdiff(1:n, i), 3); adj[i, j] <- 1 }
  adj <- pmax(adj, t(adj))
  d <- dtqw_graph_operator(adj); s <- dtqw_graph_operator_sparse(adj)
  expect_equal(as.matrix(s$U), d$U, ignore_attr = TRUE)
  expect_equal(s$arcs, d$arcs)
})

test_that("graph walk rejects asymmetric or isolated-vertex graphs", {
  bad <- matrix(c(0, 1, 0, 0), 2)
  expect_error(dtqw_graph_operator(bad))
  iso <- matrix(0, 3, 3); iso[1, 2] <- iso[2, 1] <- 1
  expect_error(dtqw_graph_operator(iso), "isolated")
})
