# Course-topic mapping: CSE 465 Principles of Big Data Management

This maps project components to the course topics as the student listed them.
The official CO numbers and wording from the SRM-AP syllabus have **not** been inserted. Fill in the `CO` column from the course handout.

| Course topic | CO | What Q-Stock implements | Evidence (file / output) |
|---|---|---|---|
| Big Data concepts, distributed file systems | _TBD_ | Volume: 40 tickers × 11.8 years daily, scaled to 7.5 M rows in Spark. Variety: prices + GDELT news tone. Velocity: daily refresh pipeline | `docs/research_questions.md`, `results/tables/spark_scaling.csv` |
| HDFS architecture and commands | _TBD_ | Curated data, code and results stored in HDFS through WebHDFS (REST) from R. Replication 1, 128 MB blocks inspected. DataNode registration fault diagnosed and fixed (include list, safe mode) | `R/hadoop_bridge.R`, `hadoop/vm_start_services.sh`, `docs/environment_report.md` |
| Hadoop and MapReduce | _TBD_ | Java MapReduce job (mapper, **combiner**, reducer, custom counters, 2 reducers) on YARN computing per ticker-month statistics. Validated against R: 5,640/5,640 groups, max error 1.7e-15 | `hadoop/QStockMonthlyStats.java`, `results/mapreduce_job.log`, `results/stage3_hadoop_hive_log.txt` |
| Hadoop ecosystem components | _TBD_ | YARN, Hive Metastore (MySQL), HiveServer2/beeline, ZooKeeper, Cloudera Manager REST API | `hadoop/vm_start_services.sh` |
| HiveQL | _TBD_ | External tables (CSV and OpenCSVSerde), GROUP BY, window functions (`ROW_NUMBER`, `RANK`), joins, a consistency check of MapReduce output vs raw rows | `hive/*.hql`, `results/tables/hive_*.tsv` |
| Spark | _TBD_ | sparklyr (no PySpark) on Spark 3.5.9: window-function features and a point-in-time range join in Spark SQL, cross-checked against R to 1e-15. Scaling to 7.5 M rows. Version incompatibility with the VM's Spark 1.6 documented | `scripts/04_spark_sparklyr.R`, `results/stage3_spark_log.txt` |
| Data analytics and ML using R | _TBD_ | DTQW, CTQW and QSW simulation; logistic regression, random forest and HAR-RV OLS; leakage-controlled walk-forward; DM tests, Holm/BH, bootstrap; 32 unit-test blocks | `R/`, `tests/`, `scripts/05*`, `scripts/11_v2_experiments.R` |

## Constraint compliance

* No PySpark anywhere; all analysis code is R. The MapReduce job is Java, the language Hadoop itself is written in.
* Hadoop and Hive run on the lab's Cloudera QuickStart VM (CDH 5.13), matching the lab environment.
