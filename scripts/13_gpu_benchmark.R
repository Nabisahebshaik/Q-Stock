# GPU vs CPU scalability of the quantum-walk simulations (torch for R, CUDA).
# Fair comparison: base R (reference BLAS) vs torch CPU (optimised, multi-threaded)
# vs torch CUDA (RTX 4060). GPU timed in float64 and float32; float32 accuracy is
# reported against float64 CPU. CUDA work is synchronised before stopping the timer.
#   Rscript scripts/13_gpu_benchmark.R

# The libtorch cu128 bundle ships its own CUDA DLLs; the cuda12.8 helper-package
# detection fails on this machine ("no file found"), so turn it off.
Sys.setenv(TORCH_CUDATOOLKIT = "FALSE")
suppressPackageStartupMessages(library(torch))
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
ensure_dirs()
stopifnot(cuda_is_available())
set.seed(11)
taus <- seq(0.2, 2, by = 0.2); steps <- 10

random_knn <- function(n, k = 4) { r <- matrix(runif(n * n), n); knn_graph((r + t(r)) / 2, k) }

timeit <- function(fun, device, reps) {
  fun()                                             # warm-up (kernel load, allocator)
  if (device == "cuda") cuda_synchronize()
  t <- numeric(reps)
  for (i in seq_len(reps)) {
    t0 <- Sys.time(); out <- fun(); if (device == "cuda") cuda_synchronize()
    t[i] <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  }
  list(sec = median(t), out = out)
}

# CTQW time-averaged |exp(-i L tau)|^2 via eigh: U = V diag(e^{-i lam tau}) V^T.
# |U_ij|^2 = (sum_k V_ik V_jk cos(lam_k tau))^2 + (sum_k V_ik V_jk sin(lam_k tau))^2  (real arithmetic)
ctqw_torch <- function(L, device, dtype) {
  Lt <- torch_tensor(L, dtype = dtype, device = device)
  e <- linalg_eigh(Lt); lam <- e[[1]]; V <- e[[2]]
  acc <- torch_zeros_like(Lt)
  for (tau in taus) {
    C <- torch_matmul(V * torch_cos(lam * tau)$unsqueeze(1), V$t())
    S <- torch_matmul(V * torch_sin(lam * tau)$unsqueeze(1), V$t())
    acc <- acc + C * C + S * S
  }
  acc / length(taus)
}

# DTQW (Grover, real operator and real initial states => real amplitudes).
dtqw_torch <- function(U, Psi0, from, n, device, dtype) {
  Ut <- torch_tensor(U, dtype = dtype, device = device)
  P <- torch_tensor(Psi0, dtype = dtype, device = device)
  # aggregation matrix arcs -> vertices (N x arcs)
  A <- matrix(0, n, length(from)); A[cbind(from, seq_along(from))] <- 1
  At <- torch_tensor(A, dtype = dtype, device = device)
  acc <- torch_zeros(n, n, dtype = dtype, device = device)
  for (s in seq_len(steps)) { P <- torch_matmul(Ut, P); acc <- acc + torch_matmul(At, P * P) }
  (acc / steps)$t()
}

ctqw_base <- function(L) {
  e <- eigen(L, symmetric = TRUE); acc <- 0
  for (tau in taus) acc <- acc + Mod(e$vectors %*% (exp(-1i * tau * e$values) * t(e$vectors)))^2
  acc / length(taus)
}

rows <- list(); acc_rows <- list()
for (n in c(50, 100, 200, 400, 800, 1600, 3200)) {
  g <- random_knn(n); L <- diag(rowSums(g$w)) - g$w
  op <- dtqw_graph_operator_sparse(g$adj); U <- as.matrix(op$U)
  Psi0 <- sapply(seq_len(n), function(i) dtqw_graph_initial_state(op$arcs, i)); Psi0 <- Re(Psi0)
  from <- op$arcs[, "from"]; reps <- if (n >= 1600) 2 else 3
  cases <- list(
    list(m = "ctqw", b = "base_R_cpu_f64", f = function() ctqw_base(L), dev = "cpu", ok = n <= 1600),
    list(m = "ctqw", b = "torch_cpu_f64", f = function() as_array(ctqw_torch(L, "cpu", torch_float64())), dev = "cpu", ok = TRUE),
    list(m = "ctqw", b = "torch_cuda_f64", f = function() ctqw_torch(L, "cuda", torch_float64()), dev = "cuda", ok = TRUE),
    list(m = "ctqw", b = "torch_cuda_f32", f = function() ctqw_torch(L, "cuda", torch_float32()), dev = "cuda", ok = TRUE),
    list(m = "dtqw", b = "torch_cpu_f64", f = function() as_array(dtqw_torch(U, Psi0, from, n, "cpu", torch_float64())), dev = "cpu", ok = n <= 1600),
    list(m = "dtqw", b = "torch_cuda_f64", f = function() dtqw_torch(U, Psi0, from, n, "cuda", torch_float64()), dev = "cuda", ok = n <= 1600),
    list(m = "dtqw", b = "torch_cuda_f32", f = function() dtqw_torch(U, Psi0, from, n, "cuda", torch_float32()), dev = "cuda", ok = n <= 1600))
  ref <- list()
  for (cs in cases) {
    if (!cs$ok) next
    r <- tryCatch(timeit(cs$f, cs$dev, reps), error = function(e) { message(n, " ", cs$b, ": ", conditionMessage(e)); NULL })
    if (is.null(r)) next
    out <- if (inherits(r$out, "torch_tensor")) as_array(r$out$cpu()) else r$out
    if (cs$b %in% c("torch_cpu_f64")) ref[[cs$m]] <- out
    err <- if (!is.null(ref[[cs$m]])) max(abs(out - ref[[cs$m]])) else NA
    rows[[length(rows) + 1]] <- data.frame(n_nodes = n, n_arcs = length(from), method = cs$m, backend = cs$b,
                                           median_seconds = r$sec, max_abs_err_vs_f64_cpu = err)
    print(tail(rows, 1)[[1]])
    if (cs$dev == "cuda") cuda_empty_cache()
  }
}
gb <- do.call(rbind, rows)
write.csv(gb, file.path(QS$paths$tables, "gpu_benchmark.csv"), row.names = FALSE)
writeLines(c(paste("torch", as.character(packageVersion("torch"))),
             paste("CUDA device capability:", paste(unlist(cuda_get_device_capability()), collapse = ".")),
             system2("nvidia-smi", c("--query-gpu=name,driver_version,memory.total", "--format=csv,noheader"), stdout = TRUE)),
           file.path(QS$paths$results, "gpu_benchmark_env.txt"))

suppressPackageStartupMessages(library(ggplot2))
gb$label <- paste(gb$method, gb$backend)
p <- ggplot(gb, aes(n_nodes, median_seconds, colour = backend, shape = backend)) +
  geom_line(linewidth = 0.5) + geom_point(size = 2.2) + scale_x_log10() + scale_y_log10() +
  facet_wrap(~method, labeller = as_labeller(c(ctqw = "CTQW (eigendecomposition)", dtqw = "DTQW (Grover, dense)"))) +
  scale_colour_manual(values = c("#2a78d6", "#eb6834", "#1baf7a", "#eda100"), name = NULL) +
  scale_shape_manual(values = c(16, 17, 15, 18), name = NULL) +
  labs(x = "Graph size N (nodes)", y = "Median seconds (all N start nodes)",
       title = "Quantum-walk simulation: CPU vs RTX 4060 (CUDA)",
       caption = "torch for R. f64/f32 = float64/float32. Accuracy of f32 vs f64 in results/tables/gpu_benchmark.csv.") +
  theme_minimal(base_size = 11) + theme(legend.position = "top", plot.background = element_rect(fill = "#fcfcfb", colour = NA))
ggsave(file.path(QS$paths$figures, "fig8_gpu_benchmark.png"), p, width = 10, height = 4.8, dpi = 300, bg = "#fcfcfb")
print(gb, digits = 3)
