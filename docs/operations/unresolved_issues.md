# Issues log

## Resolved

| # | Issue | Resolution |
|---|---|---|
| 1 | sparklyr vs the VM's Spark 1.6 / Java 7 | **Confirmed incompatible**: sparklyr 1.9.6 bundles backend JARs for Spark ≥ 2.4 only. Spark runs locally on the host instead (3.5.9, Java 17, `local[8]`) |
| 2 | No R in the VM | Analysis stays in R on the host. The VM is reached over WebHDFS + ssh/beeline. MapReduce is written in Java (JDK 1.7 in the VM) |
| 3 | Hive untested | Working: ZooKeeper + Hive started through the CM API, HiveServer2 restarted after the metastore. Tables and queries run (`results/tables/hive_*.tsv`) |
| 4 | `service X status` unreliable | Cause: services are managed by Cloudera Manager, and the init scripts are disabled |
| 4b | HDFS had **0 live DataNodes** (safe mode) | Include-list IP mismatch (127.0.0.1 vs 10.0.2.15). Runtime fix re-applied by `hadoop/vm_start_services.sh` on every boot |
| 4c | VM hung (guest unresponsive, ACPI ignored) | Forced power-off. Cloudera Management Service is now stopped after boot, leaving about 3 GB used of 7.7 GB |
| 6 | Brief 1's `spark.executor.memory` in local mode | Only driver memory is set; documented |
| 9 | Dense simulation memory | Sparse DTQW implemented and benchmarked to N = 1600 (`qw_scalability.csv`) |
| 10 | Yahoo holiday bars + NA propagation dropped AMD and truncated NSE | Holiday-bar rule in `clean_prices()`, NA-safe `trailing_mean()`, both unit-tested |
| 11 | GDELT run reported "exit 0" after failing | Wrapper scripts now check the R exit status explicitly |

## Open

| # | Issue | Impact | Next step |
|---|---|---|---|
| A | **GDELT DOC API rate limiting (HTTP 429 / connection timeouts).** Only a few tickers are fetched | The sentiment experiment (RQ5) cannot run | The overnight retry job keeps going with its cache. If it never completes, report RQ5 as not evaluated; a licensed news feed would be the alternative |
| B | Survivorship bias: the universe is today's large caps | Inflates buy-and-hold performance and may bias results | State it as a limitation, or obtain historical index constituents |
| C | Yahoo is an unofficial source; adjusted prices are back-adjusted | Fine for returns, not a point-in-time feed | Cross-check a sample against NSE bhavcopy / exchange data |
| D | GDELT archive queried today, not as of each date | Small residual look-ahead risk in sentiment | Documented in `R/sentiment_gdelt.R` |
| E | Official CSE 465 CO statements missing | CO column TBD | Copy them from the course handout |
| F | winutils.exe / hadoop.dll are third-party binaries | Supply-chain trust | Hashes recorded in `environment_report.md` |
| G | Novelty audit is preliminary (6 web searches + the student's 45-paper survey) | No novelty claims yet | Systematic Scopus / IEEE / Scholar search (`novelty_audit.md`) |
| H | Project folder is in OneDrive | Large files sync to the cloud | Move `data/` and `results/predictions*` to a non-synced path if space is a concern |
