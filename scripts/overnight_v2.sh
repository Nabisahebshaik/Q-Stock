#!/bin/bash
# Unattended overnight run of the full pipeline on data to 2026-10-21 (Git Bash, project root).
# Progress: results/overnight_v2.log. Each step continues even if an earlier optional step fails.
R="/c/Program Files/R/R-4.6.1/bin/x64/Rscript.exe"
LOG=results/overnight_v2.log
SSH="ssh -i $HOME/.ssh/qstock_vm_rsa -p 2222 -o BatchMode=yes -o ConnectTimeout=30 -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa -o KexAlgorithms=+diffie-hellman-group14-sha1 cloudera@127.0.0.1"
step() { echo "=== $(date '+%F %T') $*" | tee -a "$LOG"; }
run() { local name="$1"; shift; step "START $name"; if "$R" "$@" >> "$LOG" 2>&1; then step "OK    $name"; else step "FAIL  $name"; return 1; fi; }

step "overnight v2 run begins"
run tests          tests/run_tests.R
run dataset        scripts/02_build_dataset.R || exit 1          # everything below needs it
run qsw_features   scripts/10_qsw_features.R 10
run v2_experiments scripts/11_v2_experiments.R
run v1_main        scripts/05_experiments.R main
run naive          scripts/05b_naive_baseline.R
run ablations      scripts/06_ablations.R
run scalability    scripts/07_scalability.R
run spark          scripts/04_spark_sparklyr.R
if $SSH true 2>/dev/null; then run hadoop_hive scripts/03_hadoop_hive.R; else step "SKIP hadoop_hive (VM unreachable)"; fi
run figures        scripts/08_figures.R
run figures_v2     scripts/12_figures_v2.R
step "overnight v2 run finished"
