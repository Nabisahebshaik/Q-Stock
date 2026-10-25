---
name: hadoop-hive-spark-pipeline
description: Operate the Q-Stock Big Data layer from R on Windows - start the Cloudera QuickStart VM 5.13 and its services, move files to HDFS over WebHDFS, run the Java MapReduce job on YARN, create and query Hive external tables through beeline, and run Spark 3.5 locally through sparklyr with cross-checks against R. Use for anything touching hadoop/, hive/, scripts/03_hadoop_hive.R, scripts/04_spark_sparklyr.R, R/hadoop_bridge.R or the VM.
---

# Hadoop / Hive / Spark pipeline (R-driven)

Constraint: no PySpark, no R inside the VM. R on the host drives everything.

## 1. Start the VM (after every host boot)

```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" startvm "cloudera-quickstart-vm-5.13.0-0-virtualbox" --type headless
```
Wait ~5 min, then from Git Bash:
```bash
ssh -i ~/.ssh/qstock_vm_rsa -p 2222 -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa -o KexAlgorithms=+diffie-hellman-group14-sha1 cloudera@127.0.0.1 'bash -s' < hadoop/vm_start_services.sh
```
The script re-applies the **DataNode include-list fix** (CM writes 127.0.0.1, the DataNode is 10.0.2.15 → 0 live DataNodes, safe mode), starts ZooKeeper + Hive via the Cloudera Manager REST API (v18), and restarts HiveServer2 if it beat the metastore.

Gotchas:
- `service X status` always says "not running" (CM-managed); check with `hdfs dfsadmin -report`, `yarn node -list`, the CM API or `netstat`.
- Keep the Cloudera Management Service **stopped**; with it on, the 8 GB guest hangs.
- Shut down cleanly: `sudo shutdown -h now` in the VM or `VBoxManage controlvm ... acpipowerbutton`.

## 2. HDFS from R (`R/hadoop_bridge.R`)

WebHDFS REST on `http://127.0.0.1:50070/webhdfs/v1` (NAT-forwarded): `hdfs_mkdirs`, `hdfs_put`, `hdfs_ls`, `hdfs_get_text`, `hdfs_delete`. Root: `/user/cloudera/qstock` (`curated/prices`, `raw/sentiment`, `code`, `results/...`). `vm_ssh()` runs commands in the guest (beeline, `hadoop jar`).

## 3. MapReduce (Java 7 in the VM)

`hadoop/QStockMonthlyStats.java`: mapper → **combiner** → 2 reducers with custom counters, per ticker-month stats. Compile and run in the guest via `vm_ssh`. Always validate against an independent R computation (current: 5,680 groups, max error 1.8×10⁻¹⁵).

## 4. Hive (1.1, HiveServer2 :10000)

- `hive/01_market_tables.hql`, `02_results_tables.hql`: EXTERNAL tables over HDFS CSV (OpenCSVSerde where quoted).
- `03_*`, `04_*`: GROUP BY, `ROW_NUMBER`/`RANK` windows, joins, and an MR-vs-raw consistency query that must return 0 mismatches.
- Run through beeline over ssh; save outputs to `results/tables/hive_*.tsv`.
- After new experiment results, re-run `scripts/03_hadoop_hive.R` to reload them.

## 5. Spark via sparklyr (host, not the VM)

sparklyr 1.9.6 has no backend for the VM's Spark 1.6 / Java 7, so Spark 3.5.9 runs locally (`local[8]`, Java 17, `sparklyr.shell.driver-memory = 8G`; `spark.executor.memory` does nothing in local mode). Windows needs `winutils.exe` + `hadoop.dll` on `HADOOP_HOME/bin` (see top of `scripts/04_spark_sparklyr.R`). Pattern: dplyr window functions / Spark SQL range join → collect → compare with base R (tolerance ~1e-12) → scaling run replicating the table ×1..×64.

## Resource budget

20 host threads: ranger 4, Spark 8, VM 4 vCPU. 8 GB of 24 GB RAM goes to the VM while it runs.
