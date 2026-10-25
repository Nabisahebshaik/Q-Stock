# Environment report

Inspected and set up on 2026-10-22. Every value below was read from the machine, not assumed.

## Windows host (development, R analysis, local Spark)

| Item | Observed / installed |
|---|---|
| OS | Windows 11 Home Single Language 10.0.26300 |
| Machine | Lenovo Legion 5 (83JJ000DIN, as stated by the user) |
| CPU | Intel Core **i7-13650HX**, 14 cores / 20 threads (read from Win32_Processor; an earlier brief said "13650H") |
| RAM | 2 x 12 GB DDR5-4800 (23.7 GB usable); 8 GB of it goes to the Cloudera VM while it runs |
| Disk | 512 GB PCIe 4.0 NVMe (as stated by the user) |
| Thread use | ranger `num.threads = 4`, Spark `local[8]`, VM 4 vCPU: deliberately below 20 threads so the VM is not starved |
| GPU | NVIDIA GeForce RTX 4060 Laptop, 8 GB, driver 572.16. **Not used**; see "GPU decision" below |
| R | **4.6.1** (`winget install RProject.R`), at `C:\Program Files\R\R-4.6.1\bin\x64\Rscript.exe` (not on PATH) |
| R packages | testthat 3.3.2, sparklyr 1.9.6, dplyr 1.2.1, ranger 0.18.0, ggplot2 4.0.3, bench 1.1.4, curl, jsonlite, DBI |
| BLAS | R's reference BLAS (single-threaded); all timings use it |
| Java | **Temurin OpenJDK 17.0.20.1** (`winget install EclipseAdoptium.Temurin.17.JDK`), used only for local Spark |
| Spark | **3.5.9** (hadoop3 build) in `%LOCALAPPDATA%\spark\spark-3.5.9-bin-hadoop3`, SHA-512 verified against downloads.apache.org |
| winutils | `winutils.exe` + `hadoop.dll` (Hadoop 3.3.6 build from github.com/cdarlint/winutils, a **third-party binary**) in `...\spark-3.5.9-bin-hadoop3\tmp\hadoop\bin`. sha256 winutils `496a591e…8553`, hadoop.dll `d7ab36a6…05be3` |
| VirtualBox | 7.2.14r174565 |

WSL Ubuntu 24.04.3 exists (about 11 GB RAM visible) but has no Java, R, Hadoop or Spark and is unused.

## Cloudera QuickStart VM (`cloudera-quickstart-vm-5.13.0-0-virtualbox`)

| Item | Observed |
|---|---|
| Guest OS | CentOS 6.7, kernel 2.6.32-573.el6.x86_64 |
| VM resources | 8192 MB RAM, 4 vCPU, 55 GB root disk |
| Java | Oracle JDK **1.7.0_67** |
| Hadoop / HDFS / YARN | **2.6.0-cdh5.13.0**; single DataNode, replication 1, block size 128 MB |
| Hive | **1.1.0-cdh5.13.0**, HiveServer2 on 10000, metastore on 9083, MySQL backend |
| Spark | **1.6.0** only (no Spark 2 parcel) |
| R / Python | no R; Python 2.6.6 |
| Service management | **Cloudera Manager 5.13** (REST API v18, admin/admin). The `/etc/init.d/hadoop-*` and `hive-*` scripts are disabled, so `service X status` always reports "not running"; check with `hdfs dfsadmin -report`, `yarn node -list`, the CM API or `netstat` instead |
| Guest Additions | 5.0.14 (old; `guestcontrol` works only for short commands) |

### Changes made to the VM in this project (all reversible)

1. NAT rule `qstock-ssh`: host 127.0.0.1:2222 to guest 22.
2. `~/.ssh/authorized_keys` for user `cloudera` holds the key `qstock`. `chmod g-w /home/cloudera` was needed because sshd StrictModes rejected the key.
3. **DataNode include-list fix.** Cloudera Manager writes `127.0.0.1` into the NameNode's `dfs_hosts_allow.txt`, while `/etc/hosts` maps `quickstart.cloudera` to `10.0.2.15`. The DataNode was refused ("host is not in the include-list"), HDFS had 0 live DataNodes and the NameNode stayed in safe mode.
   Earlier `hdfs dfs -ls` worked only because listing needs no DataNode.
   The fix appends 10.0.2.15 and runs `-refreshNodes`. It is runtime-only (CM regenerates the file) and is re-applied by `hadoop/vm_start_services.sh`.
4. ZooKeeper and Hive started through the CM API (they were stopped). HiveServer2 must be restarted if it starts before the metastore.
5. The Cloudera Management Service (monitoring roles) is stopped after boot. With it running alongside HDFS, YARN, ZooKeeper and Hive, the guest became completely unresponsive and needed a forced power-off.
   With it stopped, the guest used about 3.0 GB of 7.7 GB and stayed stable.

## sparklyr compatibility: resolved

* sparklyr 1.9.6 ships backend JARs only for Spark 2.4, 3.0, 3.5 and 4.x (`sparklyr/java/`). Its NEWS says the Java code for Spark 2.3 and below was removed.
  **It cannot drive the VM's Spark 1.6.0**, and the VM's Java 7 is too old for the bundled JARs anyway.
* Decision: Spark runs **locally on the host** (Spark 3.5.9, `local[8]`, Java 17) through sparklyr. PySpark is not used anywhere.
* In local mode the executor runs inside the driver JVM, so only `sparklyr.shell.driver-memory` (8G) is set. `spark.executor.memory` has no effect there.

## GPU decision

The quantum-walk simulations run on market graphs of N = 20 nodes per market. Measured cost (`results/tables/qw_scalability.csv`) is in milliseconds at that size, so a GPU would add transfer overhead and dependencies (CUDA build of `torch` for R, about 2 GB) for no benefit.
The scalability study shows where a GPU would start to matter (dense methods at N in the high hundreds or more); see `docs/results/results.md`.
