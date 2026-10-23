# v2: QSW features for the pre-registered omega grid (+ random-graph controls),
# computed in parallel (PSOCK cluster; one job per market x omega x graph).
# Output: data/curated/qsw_features.rds (long format) and data/curated/vol_targets.rds
#   Rscript scripts/10_qsw_features.R [workers=10]

for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
ensure_dirs()
workers <- as.integer(commandArgs(trailingOnly = TRUE)[1]); if (is.na(workers)) workers <- 10

OMEGAS <- c(0, 0.1, 0.25, 0.5, 0.75, 0.9, 1)   # pre-registered grid (docs/preregistration_v2.md)
prices <- clean_prices(load_market_data())$data
jobs <- c(
  apply(expand.grid(market = c("NSE", "NASDAQ"), omega = OMEGAS, graph = "corr",
                    stringsAsFactors = FALSE), 1, as.list),
  apply(expand.grid(market = c("NSE", "NASDAQ"), omega = c(0, 1), graph = "random",
                    stringsAsFactors = FALSE), 1, as.list))
message(length(jobs), " jobs on ", workers, " workers")

cl <- parallel::makeCluster(workers)
parallel::clusterExport(cl, "prices")
parallel::clusterEvalQ(cl, for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f))
t0 <- Sys.time()
res <- parallel::parLapplyLB(cl, jobs, function(j) {
  om <- as.numeric(j$omega)
  t1 <- Sys.time()
  f <- qsw_features_market(prices[prices$market == j$market, ], om, graph = j$graph)
  f$market <- j$market; f$omega <- om; f$graph <- j$graph
  attr(f, "secs") <- as.numeric(difftime(Sys.time(), t1, units = "secs"))
  f
})
parallel::stopCluster(cl)
secs <- sapply(res, attr, "secs")
message("total wall time ", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1),
        " min; per job mean ", round(mean(secs)), " s")
qf <- do.call(rbind, res)
saveRDS(qf, file.path(QS$paths$curated, "qsw_features.rds"))
saveRDS(build_vol_targets(prices), file.path(QS$paths$curated, "vol_targets.rds"))
write.csv(data.frame(job = sapply(jobs, function(j) paste(j$market, j$omega, j$graph)), seconds = secs),
          file.path(QS$paths$tables, "qsw_feature_job_times.csv"), row.names = FALSE)
print(aggregate(cbind(q_self, q_ent) ~ omega + graph, qf, mean))
