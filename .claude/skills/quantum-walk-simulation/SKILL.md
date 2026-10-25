---
name: quantum-walk-simulation
description: Classically simulate discrete-time (DTQW), continuous-time (CTQW) and quantum stochastic walks (QSW, Lindblad with a quantum-to-classical dial omega) on weighted graphs in R, derive node features, and verify them with physics invariants. Use when writing, changing, debugging or benchmarking quantum-walk code, market-graph walk features, or the QSW dial in Q-Stock (R/dtqw.R, R/ctqw.R, R/qsw.R, R/market_graph.R, R/qsw_features.R).
---

# Quantum-walk simulation in R

All walks are **classical simulations** with dense or sparse linear algebra. Never claim quantum hardware or speed-up.

## Building blocks (Q-Stock)

| Walk | File | Construction |
|---|---|---|
| CTQW | `R/ctqw.R` | H = L = D − W; `P(t) = |exp(−iHt)|²` via eigendecomposition of the symmetric H |
| DTQW | `R/dtqw.R` | Grover coin on the arc space of the (unweighted) kNN graph; flip-flop shift; vertex probability = sum over outgoing arcs. Dense and `Matrix::sparseMatrix` versions |
| QSW | `R/qsw.R` | `dρ/dt = −(1−ω)i[H,ρ] + ω Σ γ_ij(L_ij ρ L_ij† − ½{L_ij†L_ij, ρ})`, L_ij = \|i⟩⟨j\|, γ = W |
| Classical controls | `R/market_graph.R` | random walk D⁻¹W (steps 1..10), heat kernel exp(−τL), personalised PageRank (α = 0.85) |

## QSW implementation pattern

1. Integrate **all N start states at once** as an N×N×N complex array with RK4 (h = 0.02); one call returns the full P (row = start node).
2. Use the closed-form dissipator: `Σ γ L ρ L† = diag(W p)` (p = populations) and `Σ γ L†L = diag(rowSums(W))`. Never build N² jump operators.
3. Average P over τ ∈ {0.2, …, 2}; clip tiny negatives (`pmax(P, 0)`) and renormalise rows.
4. `exact_limits = TRUE` uses eigendecomposition at ω ∈ {0, 1}. Use it for interactive/live speed only; research scripts keep the integrator so published results reproduce.

## Node features (identical for every method so comparisons are fair)

`self = P[i,i]`, `mom` = P-weighted mean of neighbours' z-scored 5-day returns, `ent` = Shannon entropy of `P[i,]`, `volspill` = P-weighted mean of neighbours' log 5-day RV. Compute them from the same graph for every walk method.

## Verification checklist (add a testthat block for each new operator)

- DTQW operator unitary: `is_unitary(U)` (‖U†U − I‖ < 1e-10); probabilities sum to 1 every step.
- CTQW Hamiltonian Hermitian: `is_hermitian(H)`; P rows sum to 1.
- QSW: trace(ρ) = 1, ρ Hermitian, purity ≤ 1; **ω = 0 matches CTQW and ω = 1 matches exp(−tL) to 1e-6**.
- Sparse DTQW equals dense DTQW on small graphs.
- Run `Rscript tests/run_tests.R` (tests live in `tests/testthat/test_{dtqw,ctqw,qsw}.R`).

## Performance notes

- N = 20 nodes per market: milliseconds per walk on CPU; no GPU needed.
- Dense methods get expensive at N in the high hundreds; sparse DTQW benchmarked to N = 1600 (`scripts/07_scalability.R`).
- GPU (torch for R): CUDA float32 is the fast path (CTQW N = 1600: 0.145 s vs 62 s base R); float64 is *not* faster than CPU on a consumer GPU; no gain below ~200 nodes (`scripts/13_gpu_benchmark.R`).
- On constrained containers set `OPENBLAS_NUM_THREADS=1`; BLAS thread contention made a 20-node QSW 20× slower.
