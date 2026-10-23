#!/bin/bash
# Replacement for the GPU waiters that the memory-pressure reaper stopped on 2026-10-23.
# Waits for the resumed GPU benchmark (Windows PID given as $1), then finishes
# after_overnight_gpu.sh (v2 figures) and after_gpu_mlp.sh (GPU MLP/QLIKE).
#   bash scripts/resume_gpu_chain.sh 24132
R="/c/Program Files/R/R-4.6.1/bin/x64/Rscript.exe"
LOG=results/overnight_v2.log
PID=$1
step() { echo "=== $(date '+%F %T') $*" | tee -a "$LOG"; }
while tasklist //FI "PID eq $PID" 2>/dev/null | grep -q "$PID"; do sleep 30; done
if [ results/tables/gpu_benchmark.csv -nt results/gpu_benchmark_resume.stamp ]; then
  step "OK    gpu_benchmark"; else step "FAIL  gpu_benchmark (no fresh gpu_benchmark.csv)"; fi
"$R" scripts/12_figures_v2.R >> "$LOG" 2>&1 && step "OK    figures_v2 (rerun)"
step "all overnight work finished"
step "START mlp_qlike_gpu (smoke, 2 folds)"
if "$R" scripts/18_mlp_qlike_gpu.R 2 >> "$LOG" 2>&1; then
  step "OK    mlp smoke; START full run"
  if "$R" scripts/18_mlp_qlike_gpu.R >> "$LOG" 2>&1; then step "OK    mlp_qlike_gpu"; else step "FAIL  mlp_qlike_gpu"; fi
else
  step "FAIL  mlp smoke (full run skipped)"
fi
step "gpu mlp work finished"
