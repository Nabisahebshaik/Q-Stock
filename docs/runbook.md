# Runbook: reproducing Q-Stock end to end

All commands run from the project root (`Desktop\Q-Stock`) in PowerShell unless noted.
`Rscript` means `& "C:\Program Files\R\R-4.6.1\bin\x64\Rscript.exe"`.

## 0. One-time setup (already done on this laptop on 2026-10-22)

| Component | How it was installed |
|---|---|
| R 4.6.1 | `winget install RProject.R` |
| R packages | testthat, jsonlite, curl, ranger, ggplot2, bench, sparklyr, dplyr, DBI (CRAN) |
| JDK 17 (for local Spark) | `winget install EclipseAdoptium.Temurin.17.JDK` |
| Spark 3.5.9 for sparklyr | tarball from an Apache mirror, SHA-512 checked against downloads.apache.org, then `sparklyr::spark_install_tar()` |
| VM SSH access | key `~/.ssh/qstock_vm_rsa`; NAT rule `qstock-ssh` (host 127.0.0.1:2222 to guest 22); `chmod g-w /home/cloudera` in the VM (sshd StrictModes) |

## 1. Start the Cloudera VM and its services (after every boot)

```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" startvm "cloudera-quickstart-vm-5.13.0-0-virtualbox" --type headless
# wait ~5 minutes for Cloudera Manager, then (Git Bash):
ssh -i ~/.ssh/qstock_vm_rsa -p 2222 -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa \
    -o KexAlgorithms=+diffie-hellman-group14-sha1 cloudera@127.0.0.1 'bash -s' < hadoop/vm_start_services.sh
```

`vm_start_services.sh` does three things:
1. Applies the DataNode include-list fix (see `docs/unresolved_issues.md`, item 4).
2. Starts ZooKeeper and Hive through the Cloudera Manager REST API.
3. Restarts HiveServer2 if it came up before the metastore.

Shut the VM down cleanly with `sudo shutdown -h now` inside the VM, or `VBoxManage controlvm ... acpipowerbutton`.

## 2. Pipeline

| Step | Command | Needs VM | Output |
|---|---|---|---|
| Tests | `Rscript tests/run_tests.R` | no | console |
| Stage 1 demo | `Rscript scripts/01_stage1_prototype.R` | no | `results/stage1_*` |
| Data + features | `Rscript scripts/02_build_dataset.R` | no | `data/curated/dataset_graph.rds`, `results/data_quality_report.txt` |
| HDFS + MapReduce + Hive | `Rscript scripts/03_hadoop_hive.R` | **yes** | `results/stage3_hadoop_hive_log.txt`, `results/tables/hive_*.tsv` |
| Spark (sparklyr) | `Rscript scripts/04_spark_sparklyr.R` | no | `results/stage3_spark_log.txt`, `results/tables/spark_scaling.csv` |
| Main experiments | `Rscript scripts/05_experiments.R main` | no | `results/tables/experiment_results.csv` and others |
| Sentiment experiment | `Rscript scripts/05_experiments.R sentiment` | no | needs the complete GDELT download |
| Ablations | `Rscript scripts/06_ablations.R` | no | `results/tables/ablation_results.csv` |
| Scalability | `Rscript scripts/07_scalability.R` | no | `results/tables/qw_scalability.csv` |
| Figures + md tables | `Rscript scripts/08_figures.R` | no | `results/figures/*.png`, `results/tables/*.md` |

After step 05, re-run step 03 to load the experiment results and predictions into Hive.

### v2 and extras

| Step | Command | Output |
|---|---|---|
| QSW features (parallel) | `Rscript scripts/10_qsw_features.R 10` | `data/curated/qsw_features.rds` |
| Pre-registered v2 tests | `Rscript scripts/11_v2_experiments.R` | `results/tables/v2_*.csv` |
| v2 figures | `Rscript scripts/12_figures_v2.R` | `fig7_quantumness_dial.png` |
| GPU benchmark | `Rscript scripts/13_gpu_benchmark.R` | `gpu_benchmark.csv`, `fig8` |
| Robustness / SHAP / economic value | `scripts/14`, `15`, `16` | `v2_robustness_*`, `explainability_*`, `v2_economic_value*` |
| GHAR + Model Confidence Set | `Rscript scripts/17_ghar_mcs.R` | `v2_ghar_*.csv`, `v2_mcs.csv` |
| GPU MLP (QLIKE) | `Rscript scripts/18_mlp_qlike_gpu.R` | `v2_mlp_qlike_gpu*.csv` |
| Power analysis | `Rscript scripts/19_power_analysis.R` | `power_analysis*.csv` |
| Dashboard | `Rscript -e "shiny::runApp('app', port = 8050, launch.browser = TRUE)"` | browser; Live market tab: `http://127.0.0.1:8050/?tab=Live%20market` (needs internet; NSE 09:15–15:30 IST, NASDAQ 09:30–16:00 New York) |
| Dashboard screenshot | `Rscript scripts/22_dashboard_screenshot.R "Live market" 25` (dashboard must be running; uses Edge via chromote) | `results/screenshots/` |

GPU scripts set `TORCH_CUDATOOLKIT=FALSE`: the libtorch cu128 bundle ships its own CUDA DLLs.
Thermal safety for long runs: `powershell -ExecutionPolicy Bypass -File scripts/thermal_guard.ps1 -Hours 14`.

Price data is cached in `data/raw/prices_yahoo.csv`. Sentiment is cached per ticker in `data/raw/gdelt_cache/`. Delete those files to re-download.
