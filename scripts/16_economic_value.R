# EXPLORATORY economic value of the T1 volatility forecasts (not pre-registered).
# Daily-rebalanced long-only inverse-volatility portfolio per market:
#   w_i,t proportional to 1 / sigma_hat_i,t,  sigma_hat = exp(pred / 2)  (pred = log 5-day mean r^2)
# using forecasts formed at the close of t, applied to the return from t to t+1.
# Compared: HAR-RV, QSW omega = 0.25, QSW omega = 1 (classical), equal weight.
# Costs: 10 bps per unit of one-way turnover.

for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
pd <- file.path(QS$paths$results, "predictions_v2")
ds <- readRDS(file.path(QS$paths$curated, "dataset_graph.rds"))
cost <- QS$cost_bps / 1e4

port <- function(pr, rets) {
  m <- merge(pr[, c("date", "ticker", "pred")], rets, by = c("date", "ticker"))
  m <- m[order(m$date, m$ticker), ]
  m$inv <- exp(-m$pred / 2)
  m$w <- ave(m$inv, m$date, FUN = function(x) x / sum(x))
  wide <- reshape(m[, c("date", "ticker", "w")], idvar = "date", timevar = "ticker", direction = "wide")
  W <- as.matrix(wide[, -1]); W[is.na(W)] <- 0
  turnover <- c(1, rowSums(abs(diff(W))))
  daily <- aggregate(cbind(r = w * (exp(next_ret) - 1)) ~ date, m, sum)
  daily$r_net <- daily$r - turnover[match(daily$date, wide$date)] * cost
  daily
}
summ <- function(d, name, mk) data.frame(market = mk, portfolio = name,
  ann_return = mean(d$r_net) * 252, ann_vol = sd(d$r_net) * sqrt(252),
  sharpe = annualized_sharpe(d$r_net), max_drawdown = { e <- cumprod(1 + d$r_net); max(1 - e / cummax(e)) })

out <- list(); diffs <- list()
for (mk in c("NSE", "NASDAQ")) {
  rets <- ds[ds$market == mk, c("date", "ticker", "next_ret")]
  ps <- list(HAR = "baseline", `QSW w=0.25` = "qsw_w025", `QSW w=1 (classical)` = "qsw_w100")
  dl <- lapply(ps, function(v) port(readRDS(file.path(pd, sprintf("T1_%s_%s.rds", mk, v))), rets))
  ew <- aggregate(cbind(r = exp(next_ret) - 1) ~ date, rets[rets$date %in% dl[[1]]$date, ], mean); ew$r_net <- ew$r
  for (nm in names(dl)) out[[length(out) + 1]] <- summ(dl[[nm]], nm, mk)
  out[[length(out) + 1]] <- summ(ew, "Equal weight", mk)
  # Paired comparison of daily squared portfolio returns (lower realised risk is better).
  a <- merge(dl[["QSW w=0.25"]], dl[["QSW w=1 (classical)"]], by = "date")
  ci <- stationary_boot_ci(a$r_net.x^2 - a$r_net.y^2, reps = 1000)
  diffs[[length(diffs) + 1]] <- data.frame(market = mk, comparison = "squared return: QSW w=0.25 minus w=1",
                                           mean = ci[["mean"]], lo = ci[["lo"]], hi = ci[["hi"]])
}
ev <- do.call(rbind, out); dv <- do.call(rbind, diffs)
write.csv(ev, file.path(QS$paths$tables, "v2_economic_value.csv"), row.names = FALSE)
write.csv(dv, file.path(QS$paths$tables, "v2_economic_value_diff.csv"), row.names = FALSE)
print(ev, digits = 4); print(dv, digits = 3)
