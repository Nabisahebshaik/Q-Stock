# Q-Stock assistant: answers questions about the dashboard, the live forecast and its
# explanation, news, and the research findings. Deterministic and grounded: every number
# in a reply is read from the same functions the API endpoints use or from the results
# CSVs, each reply lists its sources, and anything unavailable is said to be unavailable.
# It gives no buy/sell advice. No external language model is called.
#
# ctx: list of functions supplied by the API (stubs in the tests)
#   live(mk) -> /api/live payload    forecast(mk) -> forecast data frame or NULL
#   explain(mk, tk) -> explain_forecast() or NULL    news(mk, tk) -> list(items, errors)
#   table(file) -> data frame from results/tables or NULL

assistant_universe <- function() {
  stop_words <- c("state", "bank", "tata", "hindustan", "sun", "texas", "advanced", "bharti", "asian", "larsen", "hdfc", "icici", "axis", "kotak", "bajaj", "hcl")
  do.call(rbind, lapply(names(QS$universe), function(mk) {
    u <- QS$universe[[mk]]
    first <- tolower(sub(" .*", "", unname(u)))
    data.frame(market = mk, ticker = names(u), label = sub("\\.NS$", "", names(u)), name = unname(u),
               alias = ifelse(nchar(first) > 3 & !first %in% stop_words, first, NA), stringsAsFactors = FALSE)
  }))
}

assistant_find_ticker <- function(text, U = assistant_universe()) {
  low <- tolower(text); words <- strsplit(gsub("[^a-z0-9&.]+", " ", low), " ")[[1]]
  hit <- which(tolower(U$label) %in% words | tolower(U$ticker) %in% words)
  if (!length(hit)) hit <- which(vapply(tolower(U$name), function(n) grepl(n, low, fixed = TRUE), TRUE))
  if (!length(hit)) hit <- which(!is.na(U$alias) & U$alias %in% words)
  if (length(hit)) U[hit[1], ] else NULL
}

assistant_intent <- function(text) {
  t <- tolower(text)
  has <- function(p) grepl(p, t, perl = TRUE)
  if (has("\\b(buy|sell|invest|should i|target price|tip|recommend)")) return("advice")
  if (has("\\b(why|explain|driver|reason|shap|contribut|xai)")) return("explain")
  if (has("\\b(news|headline|article|tweet)")) return("news")
  if (has("\\b(forecast|predict|volatil|risk|vol\\b)")) return("forecast")
  if (has("\\b(price|quote|trading at|last|change|today)")) return("quote")
  if (has("\\b(result|finding|significan|hypothes|paper|does .*quantum .*help|better than|baseline|p-?value)")) return("results")
  if (has("\\b(omega|\u03c9|dial|qsw|quantum|walk|lindblad|graph)")) return("quantum")
  if (has("\\b(hello|hi|hey|help|what can you)")) return("help")
  "unknown"
}

pct <- function(x, d = 1) ifelse(is.finite(x), sprintf(paste0("%.", d, "f%%"), 100 * x), "n/a")

assistant_reply <- function(text, ctx, market_hint = "NSE") {
  text <- substr(as.character(text %||% ""), 1, 500)
  U <- assistant_universe(); s <- assistant_find_ticker(text, U); intent <- assistant_intent(text)
  mk <- if (!is.null(s)) s$market else if (grepl("nasdaq|us market|american", tolower(text))) "NASDAQ" else market_hint
  if (!is.null(s) && intent %in% c("unknown", "help")) intent <- "forecast"
  out <- switch(intent,
    advice = ans_advice(s, mk, ctx),
    explain = if (is.null(s)) ans_need_ticker("explain") else ans_explain(s, mk, ctx),
    news = if (is.null(s)) ans_need_ticker("show news for") else ans_news(s, mk, ctx),
    forecast = if (is.null(s)) ans_market_forecast(mk, ctx) else ans_forecast(s, mk, ctx),
    quote = if (is.null(s)) ans_need_ticker("quote") else ans_quote(s, mk, ctx),
    results = ans_results(ctx),
    quantum = ans_quantum(ctx),
    help = ans_help(),
    ans_unknown())
  c(out, list(intent = intent, ticker = if (is.null(s)) NA else s$ticker, market = mk))
}

reply <- function(text, sources = character()) list(reply = paste(text, collapse = "\n"), sources = as.list(unique(sources)))

ans_help <- function() reply(c(
  "I answer from Q-Stock's own data only. Try:",
  "- *Why is RELIANCE's volatility forecast high?* (explainable forecast)",
  "- *Forecast for NVDA* or *riskiest NASDAQ stocks this week*",
  "- *Price of INFY*, *news on Apple*",
  "- *What does the quantum dial \u03c9 do?*, *Did the quantum features beat the baseline?*",
  "I don't give buy or sell advice."))

ans_unknown <- function() reply(c("I couldn't match that to something Q-Stock computes.",
  "I can explain a stock's volatility forecast, show its quote or news, or summarise the research results. Name a stock, e.g. *explain TCS*."))

ans_need_ticker <- function(verb) reply(sprintf("Which stock should I %s? Use a symbol (RELIANCE, AAPL) or a company name.", verb))

ans_advice <- function(s, mk, ctx) {
  r <- c("I can't tell you whether to buy or sell; Q-Stock is a research tool and its forecast is of **volatility** (how much a price moves), not direction.")
  if (!is.null(s)) { f <- ans_forecast(s, mk, ctx); r <- c(r, "", "What the model does say:", f$reply); return(reply(r, f$sources)) }
  reply(r)
}

ans_forecast <- function(s, mk, ctx) {
  f <- ctx$forecast(mk)
  if (is.null(f) || !s$ticker %in% f$ticker) return(reply(sprintf("The live volatility forecast for %s is not available right now (the daily price refresh failed or has not run).", s$label), "/api/forecast/" %s+% mk))
  i <- match(s$ticker, f$ticker); n <- nrow(f); rk <- rank(-f$pred_lrv5)[i]
  reply(c(sprintf("**%s (%s)** \u2014 forecast volatility over the next 5 sessions: **%s** annualised (as of the close of %s).",
                  s$label, s$name, pct(f$vol5_ann[i]), format(f$as_of[i])),
          sprintf("That ranks %d of %d in %s (1 = most volatile); the market median is %s.", rk, n, mk, pct(stats::median(f$vol5_ann))),
          "Model: graph-HAR regression on the stock's own and its correlation-graph neighbours' recent volatility. Ask *why* for the breakdown."),
        c(paste0("/api/forecast/", mk), "R/live_market.R ghar_live_forecast()"))
}

ans_market_forecast <- function(mk, ctx) {
  f <- ctx$forecast(mk)
  if (is.null(f)) return(reply(sprintf("The %s volatility forecast is not available right now.", mk)))
  f <- f[order(-f$vol5_ann), ]
  top <- utils::head(f, 3); bot <- utils::tail(f, 3)
  lab <- function(x) sprintf("%s %s", sub("\\.NS$", "", x$ticker), pct(x$vol5_ann))
  reply(c(sprintf("**%s 5-session volatility forecast** (as of %s):", mk, format(max(f$as_of))),
          paste("- Highest:", paste(lab(top), collapse = ", ")),
          paste("- Lowest:", paste(rev(lab(bot)), collapse = ", ")),
          sprintf("- Median: %s", pct(stats::median(f$vol5_ann)))), paste0("/api/forecast/", mk))
}

ans_explain <- function(s, mk, ctx) {
  e <- ctx$explain(mk, s$ticker)
  if (is.null(e)) return(reply(sprintf("I can't explain %s's forecast right now: the live forecast is unavailable.", s$label)))
  f <- utils::head(e$features, 3)
  lines <- sprintf("- %s: %s vs %s market average \u2192 \u00d7%.2f", f$label, pct(f$value_vol), pct(f$mean_vol), f$vol_factor)
  g <- e$groups
  reply(c(e$summary, "", "Top drivers (annualised volatility of each input, and its effect on the forecast):", lines,
          sprintf("By group: %s.", paste(sprintf("%s \u00d7%.2f", g$group, exp(g$contribution / 2)), collapse = "; ")),
          "This breakdown is exact for the linear model (the factors multiply to the forecast \u00f7 the market average)."),
        c(paste0("/api/explain/", mk, "/", s$ticker), "R/explain.R"))
}

ans_quote <- function(s, mk, ctx) {
  l <- tryCatch(ctx$live(mk), error = function(e) NULL)
  q <- if (!is.null(l) && length(l$quotes) && NROW(l$quotes)) l$quotes[l$quotes$ticker == s$ticker, ] else NULL
  if (is.null(q) || !nrow(q)) return(reply(sprintf("No live quote for %s right now (the feed returned nothing).", s$label), paste0("/api/live/", mk)))
  t <- format(as.POSIXct(q$last_time, origin = "1970-01-01", tz = LIVE$sessions[[mk]]$tz), "%d %b %H:%M %Z")
  cur <- if (mk == "NSE") "\u20b9" else "$"
  reply(c(sprintf("**%s** last %s%s (%s on the day), last bar %s.", s$label, cur, format(round(q$last, 2), nsmall = 2), pct(q$change, 2), t),
          if (isTRUE(l$stale)) "\u26a0 The feed is stale: this is the last good fetch." else if (!isTRUE(l$open)) "The market is closed; this is the last session's close." else NULL),
        paste0("/api/live/", mk))
}

ans_news <- function(s, mk, ctx) {
  n <- tryCatch(ctx$news(mk, s$ticker), error = function(e) NULL)
  it <- n$items
  if (is.null(it) || !NROW(it)) return(reply(sprintf("No news found for %s right now%s.", s$label,
                                                     if (length(n$errors)) " (the news feed failed)" else ""), paste0("/api/news/", mk, "/", s$ticker)))
  it <- utils::head(it, 5)
  when <- format(as.POSIXct(it$published, origin = "1970-01-01", tz = LIVE$sessions[[mk]]$tz), "%d %b %H:%M")
  reply(c(sprintf("Latest headlines for **%s**:", s$label),
          sprintf("- [%s](%s) \u2014 %s, %s", it$title, it$url, it$publisher, when)),
        c(paste0("/api/news/", mk, "/", s$ticker), unique(paste("source:", it$source))))
}

ans_results <- function(ctx) {
  h <- ctx$table("v2_hypothesis_tests.csv")
  if (is.null(h)) return(reply("The results tables are not available on this server."))
  r <- "**Pre-registered tests (volatility target T1, Holm-corrected, 5% level):**"
  for (mk in c("NSE", "NASDAQ")) for (ls in c("mse", "qlike")) {
    a <- h[h$hypothesis == "H1" & h$target == "T1" & h$loss == ls & h$market == mk, ]
    b <- h[h$hypothesis == "H2" & h$target == "T1" & h$loss == ls & h$market == mk, ]
    r <- c(r, sprintf("- %s, %s loss \u2014 QSW features vs HAR baseline: %d of %d \u03c9 settings significantly better; quantum (\u03c9<1) vs classical (\u03c9=1): %d of %d significantly *worse*, %d significantly better.",
                      mk, toupper(ls), sum(a$p_holm < 0.05 & a$mean_diff_a_minus_b < 0), nrow(a),
                      sum(b$p_holm < 0.05 & b$mean_diff_a_minus_b > 0), nrow(b), sum(b$p_holm < 0.05 & b$mean_diff_a_minus_b < 0)))
  }
  best <- h[h$hypothesis == "H2" & h$target == "T1" & h$p_holm < 0.05 & h$mean_diff_a_minus_b < 0, ]
  if (nrow(best)) {
    best <- best[order(best$mean_diff_a_minus_b), ][1, ]
    r <- c(r, sprintf("Largest significant quantum-side gain: %s, %s, \u03c9 = %.2f vs \u03c9 = 1 (Holm p = %.2g).", best$market, toupper(best$loss),
                      as.numeric(sub("qsw_w", "", best$model_a)) / 100, best$p_holm))
  }
  r <- c(r, "The results differ by market and loss, so read them per line. Full tables are on the Research tab.")
  reply(r, "results/tables/v2_hypothesis_tests.csv")
}

ans_quantum <- function(ctx) {
  g <- ctx$table("explainability_shap_groups.csv")
  sh <- if (!is.null(g)) {
    x <- g[g$task == "T1_volatility" & grepl("QSW", g$group), ]
    if (nrow(x)) sprintf("In the research explainability run, QSW features carry %s\u2013%s of the volatility model's attribution (by market and regime).",
                         pct(min(x$share_within_task), 0), pct(max(x$share_within_task), 0))
  }
  reply(c("**The quantum dial \u03c9** sets a quantum stochastic walk on the stock correlation graph (Lindblad equation, simulated classically in R \u2014 no quantum hardware):",
          "- \u03c9 = 0: a pure continuous-time quantum walk (interference, spreads fast)",
          "- \u03c9 = 1: a classical random walk; values in between mix the two.",
          "From each walk Q-Stock takes node features (how much probability stays on a stock, the entropy of its spread, volatility spill-over) and feeds them to the forecasting models.",
          sh, "See the Quantum dial tab to move \u03c9 and watch the distribution change."),
        c("R/qsw.R", if (!is.null(sh)) "results/tables/explainability_shap_groups.csv"))
}

`%s+%` <- function(a, b) paste0(a, b)
