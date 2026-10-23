# EXPLORATORY robustness of the v2 H2 result (not pre-registered; label as such).
# Uses saved T1 predictions only (no refitting):
#   1. H2 loss differences (omega vs omega = 1) by sub-period: 2017-2021 vs 2022-2026, and by year
#   2. Per-ticker consistency: share of tickers whose mean loss is lower at omega than at omega = 1
#   3. Same for H1 (vs HAR) and H3 (random graph vs HAR)

for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
pd <- file.path(QS$paths$results, "predictions_v2")
ld <- function(mk, v) { p <- readRDS(file.path(pd, sprintf("T1_%s_%s.rds", mk, v))); p$loss <- (p$y - p$pred)^2; p }
tags <- c("qsw_w000", "qsw_w010", "qsw_w025", "qsw_w050", "qsw_w075", "qsw_w090")
rows <- list(); tick_rows <- list()
for (mk in c("NSE", "NASDAQ")) {
  ref <- ld(mk, "qsw_w100"); har <- ld(mk, "baseline")
  comps <- c(setNames(as.list(tags), tags), list(qsw_w025_vs_HAR = "qsw_w025", random_w000_vs_HAR = "random_w000"))
  for (nm in names(comps)) {
    a <- ld(mk, comps[[nm]]); b <- if (grepl("vs_HAR", nm)) har else ref
    m <- merge(a[, c("date", "ticker", "loss")], b[, c("date", "ticker", "loss")], by = c("date", "ticker"))
    m$d <- m$loss.x - m$loss.y
    daily <- aggregate(d ~ date, m, mean)
    daily$period <- ifelse(daily$date < as.Date("2022-01-01"), "2017-2021", "2022-2026")
    daily$year <- format(daily$date, "%Y")
    for (grp in c("period", "year")) for (g in unique(daily[[grp]])) {
      x <- daily$d[daily[[grp]] == g]
      dm <- dm_test(x, rep(0, length(x)))
      rows[[length(rows) + 1]] <- data.frame(market = mk, comparison = ifelse(grepl("vs_HAR", nm), nm, paste(nm, "vs qsw_w100")),
                                             split = grp, group = g, n_days = length(x), mean_diff = mean(x),
                                             dm_stat = dm[["dm_stat"]], p_value = dm[["p_value"]])
    }
    tk <- aggregate(d ~ ticker, m, mean)
    tick_rows[[length(tick_rows) + 1]] <- data.frame(market = mk, comparison = nm, n_tickers = nrow(tk),
                                                     share_tickers_improved = mean(tk$d < 0),
                                                     sign_test_p = binom.test(sum(tk$d < 0), nrow(tk))$p.value)
  }
}
rb <- do.call(rbind, rows); tk <- do.call(rbind, tick_rows)
write.csv(rb, file.path(QS$paths$tables, "v2_robustness_subperiods.csv"), row.names = FALSE)
write.csv(tk, file.path(QS$paths$tables, "v2_robustness_tickers.csv"), row.names = FALSE)
print(rb[rb$split == "period", ], digits = 3); print(tk, digits = 3)
