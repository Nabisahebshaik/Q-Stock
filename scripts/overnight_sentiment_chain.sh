#!/bin/bash
# Overnight chain (Git Bash, from the project root):
#   1. patient GDELT download
#   2. sentiment experiment (only if the download completed)
#   3. Spark pipeline re-run (PIT join over all tickers)
#   4. Hive: reload sentiment + results (needs the VM; skipped if unreachable)
#   5. figures and markdown tables
R="/c/Program Files/R/R-4.6.1/bin/x64/Rscript.exe"
LOG=results/overnight_chain.log
SSH="ssh -i $HOME/.ssh/qstock_vm_rsa -p 2222 -o BatchMode=yes -o ConnectTimeout=30 -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa -o KexAlgorithms=+diffie-hellman-group14-sha1 cloudera@127.0.0.1"
step() { echo "=== $(date '+%F %T') $*" >> "$LOG"; }

step "GDELT download"
if "$R" scripts/fetch_sentiment_overnight.R 14 >> "$LOG" 2>&1; then
  step "sentiment experiment";  "$R" scripts/05_experiments.R sentiment >> "$LOG" 2>&1 || step "FAILED sentiment experiment"
  step "spark pipeline";        "$R" scripts/04_spark_sparklyr.R >> "$LOG" 2>&1 || step "FAILED spark"
  if $SSH true 2>/dev/null; then
    step "hive";                "$R" scripts/03_hadoop_hive.R >> "$LOG" 2>&1 || step "FAILED hive"
  else
    step "VM unreachable: skipped hive"
  fi
else
  step "GDELT download incomplete: sentiment steps skipped"
fi
step "figures";                 "$R" scripts/08_figures.R >> "$LOG" 2>&1 || step "FAILED figures"
step "done"
