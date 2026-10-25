---
name: gpu-and-long-run-safety
description: Run long unattended R jobs safely on the Windows laptop - GPU work with torch for R and CUDA (benchmarks, QLIKE-trained MLP), overnight Git Bash job chains with explicit exit-status checks and log markers, a PowerShell thermal guard that pauses processes and the VM at 87 C, and a system health logger. Use when planning, launching, resuming or checking overnight runs or GPU experiments.
---

# GPU and long-run safety

## Torch for R + CUDA

- RTX 4060 Laptop 8 GB. Set `TORCH_CUDATOOLKIT=FALSE` before loading torch: the libtorch cu128 bundle ships its own CUDA DLLs.
- Use **float32 on CUDA**; float64 is not faster than CPU on a consumer GPU (218 GFLOP/s f64 vs 7.6 TFLOP/s f32). Report f32 error vs a torch CPU float64 reference.
- GPU helps only for large graphs (≥ ~200 nodes); the study's 20-node graphs run on CPU.
- Always run a **smoke test** first (`v2_mlp_qlike_gpu_smoke.csv`), then the full run. Only one job may use the GPU at a time; kill duplicate waiters.
- Benchmarks: median of 3 runs (2 for N ≥ 1600), save `results/gpu_benchmark_env.txt`.

## Overnight chains (`scripts/overnight_*.sh`, `after_*.sh`, `resume_gpu_chain.sh`)

- One log per chain (`results/overnight_v2.log`); each step writes `=== <step> OK` or `=== <step> FAIL`; the chain ends with a fixed sentence (e.g. `overnight v2 run finished`).
- Check `$?` of every `Rscript` explicitly — an earlier wrapper reported "exit 0" after R failed.
- Waiters (`after_*.sh`) poll for the previous chain's final line, then start.
- Check progress with `grep "===" results/overnight_v2.log`; re-run a FAIL step by hand.
- Record start/end times so runtime measurements can be shown not to overlap other jobs.

## Thermal and resource guard

- User rule: **pause at 87 °C (GPU) or CPU throttling, resume at 50–65 °C.**
- `powershell -ExecutionPolicy Bypass -File scripts/thermal_guard.ps1 -Hours 14` suspends R/Java and pauses the VM; logs to `results/thermal_guard.log` (UTF-16).
- `scripts/monitor_system.ps1` writes a health row every 5 min to `results/system_monitor.csv`.
- Windows' memory-pressure reaper can kill the guard and waiters; after resuming, check that each chain is still alive and restart only what is missing.
- Thread budget: ranger 4, Spark 8, VM 4 vCPU of 20 threads; leave headroom.
- Stop the guard/logger when the user says they are monitoring.
