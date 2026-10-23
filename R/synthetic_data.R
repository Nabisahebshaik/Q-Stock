# Synthetic market data for SOFTWARE VALIDATION ONLY.
#
# Prices follow a GARCH(1,1) process with Student-t shocks, which gives fat
# tails and volatility clustering but NO predictable direction. Any model that
# scores well above chance on this data is a sign of a bug or leakage, not skill.

simulate_garch_prices <- function(n_days = 750, tickers = c("SYN_A", "SYN_B", "SYN_C"),
                                  start_date = as.Date("2021-01-01"),
                                  omega = 2e-6, alpha = 0.08, beta = 0.90,
                                  df = 5, mu = 0.0002, seed = 42) {
  stopifnot(alpha + beta < 1)
  set.seed(seed)
  dates <- seq(start_date, by = "day", length.out = round(n_days * 7 / 5) + 10)
  dates <- dates[!format(dates, "%u") %in% c("6", "7")][seq_len(n_days)]

  out <- lapply(tickers, function(tk) {
    sigma2 <- numeric(n_days)
    r <- numeric(n_days)
    sigma2[1] <- omega / (1 - alpha - beta)
    z <- rt(n_days, df) / sqrt(df / (df - 2))   # unit-variance t shocks
    for (t in seq_len(n_days)) {
      if (t > 1) sigma2[t] <- omega + alpha * (r[t - 1] - mu)^2 + beta * sigma2[t - 1]
      r[t] <- mu + sqrt(sigma2[t]) * z[t]
    }
    close <- 100 * exp(cumsum(r))
    open <- close * exp(-r * runif(n_days))
    high <- pmax(open, close) * (1 + abs(rnorm(n_days, 0, 0.003)))
    low  <- pmin(open, close) * (1 - abs(rnorm(n_days, 0, 0.003)))
    data.frame(date = dates, ticker = tk, open = open, high = high, low = low,
               close = close, volume = round(rlnorm(n_days, 13, 0.4)))
  })
  do.call(rbind, out)
}
