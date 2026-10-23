#!/bin/bash
# Wait until all overnight work (incl. GPU benchmark) is finished, then run the
# exploratory GPU MLP/QLIKE experiment. The thermal guard stays active throughout.
R="/c/Program Files/R/R-4.6.1/bin/x64/Rscript.exe"
LOG=results/overnight_v2.log
until grep -q "all overnight work finished" "$LOG" 2>/dev/null; do sleep 60; done
step() { echo "=== $(date '+%F %T') $*" | tee -a "$LOG"; }
step "START mlp_qlike_gpu (smoke, 2 folds)"
if "$R" scripts/18_mlp_qlike_gpu.R 2 >> "$LOG" 2>&1; then
  step "OK    mlp smoke; START full run"
  if "$R" scripts/18_mlp_qlike_gpu.R >> "$LOG" 2>&1; then step "OK    mlp_qlike_gpu"; else step "FAIL  mlp_qlike_gpu"; fi
else
  step "FAIL  mlp smoke (full run skipped)"
fi
step "gpu mlp work finished"
