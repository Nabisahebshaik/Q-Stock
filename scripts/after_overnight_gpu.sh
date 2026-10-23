#!/bin/bash
# Wait for overnight_v2.sh to finish (so CPU timings are not disturbed), then run
# the GPU benchmark and regenerate the v2 figures.
R="/c/Program Files/R/R-4.6.1/bin/x64/Rscript.exe"
LOG=results/overnight_v2.log
until grep -q "overnight v2 run finished" "$LOG" 2>/dev/null; do sleep 60; done
step() { echo "=== $(date '+%F %T') $*" | tee -a "$LOG"; }
step "START gpu_benchmark"
if "$R" scripts/13_gpu_benchmark.R >> "$LOG" 2>&1; then step "OK    gpu_benchmark"; else step "FAIL  gpu_benchmark"; fi
"$R" scripts/12_figures_v2.R >> "$LOG" 2>&1 && step "OK    figures_v2 (rerun)"
step "all overnight work finished"
