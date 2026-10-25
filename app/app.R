# Q-Stock interactive dashboard (R Shiny).
# Run from the project root:  Rscript -e "shiny::runApp('app', port = 8050, launch.browser = TRUE)"
# All quantum walks are classical simulations; the "Quantum dial" tab integrates the
# Lindblad equation live (R/qsw.R) on the selected day's real correlation graph.

suppressPackageStartupMessages({ library(shiny); library(bslib); library(visNetwork); library(DT); library(ggplot2); library(plotly) })
root <- normalizePath(file.path(getwd(), if (basename(getwd()) == "app") ".." else "."))
old <- setwd(root)
for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)
setwd(old)
P <- function(...) file.path(root, ...)
rd <- function(f) if (file.exists(P(f))) read.csv(P(f), check.names = FALSE) else NULL
addResourcePath("figs", P("results", "figures"))

# ---- data loaded once ----
setwd(root); prices <- clean_prices(load_market_data())$data; setwd(old)
RW <- lapply(split(prices, prices$market), returns_wide)
pred_dir <- P("results", "predictions_v2")
load_pred <- function(mk, v) { f <- file.path(pred_dir, sprintf("T1_%s_%s.rds", mk, v)); if (file.exists(f)) readRDS(f) else NULL }
PAL <- c(sel = "#2a78d6", ctqw = "#eb6834", classical = "#1baf7a", ink = "#0b0b0b", muted = "#52514e")
theme_app <- theme_minimal(base_size = 12) +
  theme(panel.grid.minor = element_blank(), legend.position = "top",
        panel.grid.major = element_line(colour = "#e6e5e1", linewidth = 0.3))

graph_on <- function(mk, date) {
  R <- RW[[mk]]; dts <- as.Date(rownames(R)); t <- max(which(dts <= date))
  win <- R[(t - QS$corr_window + 1):t, , drop = FALSE]
  ok <- colMeans(!is.na(win)) >= 0.8 & !is.na(R[t, ])
  rho <- suppressWarnings(cor(win[, ok], use = "pairwise.complete.obs"))
  c(knn_graph(rho, QS$knn_k), list(tick = colnames(R)[ok], date = dts[t], rho = rho))
}
taus <- QS$walk_time * seq_len(10) / 10

# ---- live market (fetchers and store can be swapped for tests via options) ----
live_fetch <- getOption("qstock.live_fetcher", fetch_intraday_many)
live_daily_fetch <- getOption("qstock.live_daily_fetcher", fetch_daily_many)
# Own DuckDB file: the API may hold LIVE$db_path open, and DuckDB allows one writer process.
live_con <- candle_store_open(getOption("qstock.live_db", P(if (store_backend() == "duckdb") LIVE$app_db_path else LIVE$sqlite_path)))
onStop(function() candle_store_close(live_con))
setwd(root); GHAR_LIVE <- lapply(c(NSE = "NSE", NASDAQ = "NASDAQ"), ghar_live_model); setwd(old)
UP <- "#1baf7a"; DOWN <- "#d64545"; FLAT <- "#c9c8c3"
pct <- function(x, d = 1) sprintf(paste0("%.", d, "f%%"), 100 * x)

# ---- UI ----
ui <- page_navbar(
  id = "nav", title = "Q-Stock", theme = bs_theme(version = 5, bootswatch = "flatly"),
  nav_panel("Overview",
    layout_columns(col_widths = c(12),
      card(card_header("What this project is"),
        p("A leakage-controlled Big Data framework that tests whether ", strong("quantum coherence"),
          " in walks on daily stock-correlation graphs helps forecasting (NSE + NASDAQ, 2015-2026)."),
        p("All quantum walks are ", strong("classical simulations"), " (no quantum hardware). Pipeline: Yahoo + GDELT → HDFS (WebHDFS) → ",
          "Hadoop MapReduce (Java) → Hive → Spark (sparklyr) → R models (walk-forward, pre-registered tests) → this dashboard."),
        uiOutput("headline")))),
  nav_panel("Live market",
    layout_sidebar(
      sidebar = sidebar(width = 300,
        radioButtons("lmk", "Market", c("NSE", "NASDAQ"), inline = TRUE),
        uiOutput("ltick_ui"),
        sliderInput("llook", "Graph window (1-minute bars)", 30, 375, 120, step = 15),
        sliderInput("lomega", HTML("&omega; (0 = quantum, 1 = classical)"), 0, 1, 0.25, step = 0.05),
        checkboxInput("lauto", "Auto-refresh every 60 s", TRUE),
        actionButton("lrefresh", "Refresh now", class = "btn-sm btn-outline-primary"),
        uiOutput("lstatus"),
        helpText("Yahoo chart API, polled; free and unofficial, so delays are possible. For viewing only: live data never enter the research results and are not trading advice.")),
      uiOutput("lboxes"),
      card(card_header(textOutput("lcandle_title")), plotlyOutput("lcandle", height = "460px")),
      layout_columns(col_widths = c(6, 6),
        card(card_header(textOutput("lnet_title")), visNetworkOutput("lnet", height = "460px"),
             card_footer("Node colour: change vs previous close (red down, grey flat, green up). Node size: intraday volatility. Links: kNN correlation of 1-minute returns.")),
        card(card_header("Live risk table"), DTOutput("ltable"))),
      card(fill = FALSE, card_header("Candle store (finalised 1-minute candles, idempotent upsert)"), verbatimTextOutput("lstore")))),
  nav_panel("Quantum dial (live)",
    layout_sidebar(
      sidebar = sidebar(width = 300,
        selectInput("mk", "Market", c("NASDAQ", "NSE")),
        dateInput("dt", "Date", value = max(prices$date), min = min(prices$date) + 120, max = max(prices$date)),
        uiOutput("start_ui"),
        sliderInput("omega", HTML("&omega; (0 = quantum CTQW, 1 = classical walk)"), 0, 1, 0.25, step = 0.05),
        helpText("Lindblad quantum stochastic walk integrated live (RK4) on this day's 60-day correlation kNN graph; distribution time-averaged over τ ∈ (0, 2].")),
      layout_columns(col_widths = c(6, 6),
        card(card_header(textOutput("graph_title")), visNetworkOutput("net", height = "460px")),
        card(card_header("Where the walk goes: selected ω vs the two limits"), plotOutput("bars", height = "460px"))),
      card(card_header("Walk statistics"), tableOutput("walkstats")))),
  nav_panel("Volatility forecasts",
    layout_sidebar(
      sidebar = sidebar(width = 300, selectInput("fmk", "Market", c("NASDAQ", "NSE")), uiOutput("ftick_ui"),
                        dateRangeInput("frange", "Period", start = as.Date("2025-01-01"), end = max(prices$date))),
      card(card_header("5-day-ahead log realised variance: realised vs out-of-sample forecasts"), plotOutput("fplot", height = "440px")),
      card(card_header("Loss for this stock over the selected period"), tableOutput("ftable")))),
  nav_panel("Results",
    navset_card_tab(
      nav_panel("Pre-registered tests (H1-H3)", DTOutput("t_h")),
      nav_panel("GHAR audit + MCS", DTOutput("t_ghar"), DTOutput("t_mcs")),
      nav_panel("Robustness", DTOutput("t_rob")),
      nav_panel("Power analysis", DTOutput("t_pow")),
      nav_panel("Direction (v1)", DTOutput("t_v1")),
      nav_panel("Figures", uiOutput("figs")))),
  nav_panel("Big Data pipeline",
    layout_columns(col_widths = c(6, 6),
      card(card_header("Hadoop MapReduce + Hive (Cloudera VM)"), verbatimTextOutput("hadoop_log")),
      card(card_header("Spark 3.5 via sparklyr"), verbatimTextOutput("spark_log"), tableOutput("spark_tbl"))),
    layout_columns(col_widths = c(6, 6),
      card(card_header("Simulation scalability (CPU)"), tableOutput("scal_tbl")),
      card(card_header("GPU benchmark (RTX 4060, CUDA)"), tableOutput("gpu_tbl")))),
  nav_panel("System health",
    card(card_header("Overnight run: CPU clock (% of max) and GPU temperature"), plotOutput("health", height = "380px")),
    card(card_header("Thermal guard log (hold at 87 °C, resume at ≤ 65 °C)"), verbatimTextOutput("guard")))
)

# ---- server ----
server <- function(input, output, session) {
  output$headline <- renderUI({
    tt <- rd("results/tables/v2_hypothesis_tests.csv")
    tagList(tags$ul(
      tags$li("Next-day direction: no model beats a naive base-rate predictor (both markets)."),
      tags$li("5-day volatility, NASDAQ: partially decoherent walks (ω≈0.25) beat their classical limit (pre-registered H2, Holm-corrected), stable over time and across 17/20 stocks."),
      tags$li("But a simple linear graph-HAR (GHAR) does as well; QSW adds nothing on top of it → no practical quantum advantage."),
      tags$li("NSE: classical limit best.")),
      if (!is.null(tt)) p(em(sprintf("%d pre-registered and secondary tests on record.", nrow(tt)))))
  })

  # Open a tab from the URL, e.g. http://127.0.0.1:8050/?tab=Live%20market
  observeEvent(session$clientData$url_search, {
    q <- parseQueryString(session$clientData$url_search)
    if (!is.null(q$tab)) nav_select("nav", q$tab)
  }, once = TRUE)

  # ---- live market ----
  store_con <- live_con
  lv <- reactiveValues(bars = NULL, meta = NULL, mk = NULL, at = NULL, errors = character(),
                       store = c(written = 0, rejected = 0), fetch_sec = NA, range = NA)
  output$ltick_ui <- renderUI({ tk <- names(QS$universe[[input$lmk]])
    selectInput("ltick", "Stock", setNames(tk, sub("\\.NS$", "", tk)), selected = if (input$lmk == "NSE") "RELIANCE.NS" else "NVDA") })
  poll <- reactive({ if (isTRUE(input$lauto)) invalidateLater(60000); input$lrefresh; req(input$lmk) })
  observeEvent(poll(), {
    mk <- poll(); tk <- names(QS$universe[[mk]]); st <- market_status(mk)
    rng <- if (isTRUE(st$open) && st$minutes_open >= 30) "1d" else "5d"   # enough bars for the graph
    t0 <- Sys.time()
    r <- tryCatch(live_fetch(tk, "1m", rng), error = function(e) list(data = list(), errors = c(all = conditionMessage(e))))
    lv$errors <- r$errors; lv$fetch_sec <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    if (!length(r$data)) return()                                           # keep last good data (shown as stale)
    s <- split_active(do.call(rbind, r$data), 60, Sys.time(), st$open)
    lv$store <- candle_upsert(store_con, s$final, 60, "yahoo_poll")
    lv$bars <- rbind(s$final, s$active); lv$n_active <- nrow(s$active)
    lv$meta <- lapply(r$data, attr, "meta"); lv$mk <- mk; lv$at <- Sys.time(); lv$range <- rng
  })
  lbars <- reactive({ req(lv$bars, identical(lv$mk, input$lmk)); lv$bars })
  lsession <- reactive(pick_session(lbars(), input$lmk))
  lrv <- reactive(intraday_rv(lsession(), input$lmk))
  lchg <- reactive(day_change(lbars(), lv$meta, input$lmk))
  lgraph <- reactive({
    b <- pick_session(lbars(), input$lmk, min_bars = 31)
    live_graph(intraday_returns_wide(b, last_n = input$llook))
  })
  lwalk <- reactive({ g <- lgraph(); validate(need(!is.null(g), "Not enough intraday bars for a graph yet.")); live_walk(g, input$lomega, lrv()) })
  lforecast <- reactive({
    mk <- input$lmk; invalidateLater(30 * 60000); m <- GHAR_LIVE[[mk]]; if (is.null(m)) return(NULL)
    d <- tryCatch(live_daily_fetch(names(QS$universe[[mk]]), mk), error = function(e) NULL)
    if (is.null(d) || is.null(d$data)) return(NULL)
    tryCatch(ghar_live_forecast(clean_prices(d$data)$data, m, mk), error = function(e) NULL)
  })

  output$lstatus <- renderUI({
    mk <- input$lmk; st <- market_status(mk); invalidateLater(15000)
    age <- if (!is.null(lv$bars) && identical(lv$mk, mk)) as.numeric(Sys.time()) - max(as.numeric(lv$bars$ts)) else NA
    badge <- function(txt, cls) tags$span(class = paste("badge", cls), style = "margin:2px;", txt)
    tagList(tags$div(style = "margin-top:8px;",
      badge(if (st$open) "Market open" else "Market closed", if (st$open) "bg-success" else "bg-secondary"),
      badge(st$local_time, "bg-light text-dark"),
      if (!is.na(age)) badge(sprintf("newest bar %s old", if (age < 120) sprintf("%.0f s", age) else sprintf("%.0f min", age / 60)),
                             if (st$open && age > 900) "bg-warning text-dark" else "bg-light text-dark"),
      if (st$open && !is.na(age) && age > 900) badge("open by clock but no recent bars (holiday?)", "bg-warning text-dark"),
      if (length(lv$errors)) badge(sprintf("%d fetch errors", length(lv$errors)), "bg-danger"),
      if (!is.null(lv$at)) badge(paste("updated", format(lv$at, "%H:%M:%S")), "bg-light text-dark")))
  })
  output$lboxes <- renderUI({
    b <- lsession(); tk <- input$ltick; req(tk %in% b$ticker)
    x <- b[b$ticker == tk, ]; x <- x[order(x$bucket), ]; ch <- lchg()[[tk]]; f <- lforecast()
    fv <- if (!is.null(f) && tk %in% f$ticker) f$vol5_ann[f$ticker == tk] else NA
    layout_columns(col_widths = c(3, 3, 3, 3),
      value_box(title = "Last price", value = formatC(tail(x$close, 1), format = "f", digits = 2, big.mark = ","),
                p(format(tail(x$bucket, 1), "%H:%M %Z", tz = LIVE$sessions[[input$lmk]]$tz))),
      value_box(title = "Change vs previous close", value = pct(ch, 2),
                theme = if (ch >= 0) value_box_theme(fg = UP) else value_box_theme(fg = DOWN)),
      value_box(title = "Intraday volatility (annualised)", value = pct(lrv()[[tk]]),
                p("from today's 1-minute returns; microstructure noise makes it higher than daily-based volatility")),
      value_box(title = "Graph-HAR 5-day volatility forecast", value = if (is.na(fv)) "n/a" else pct(fv),
                p(if (is.na(fv)) "daily data unavailable" else paste("completed sessions to", format(f$as_of[1])))))
  })
  output$lcandle_title <- renderText({
    req(input$ltick); sprintf("%s, 1-minute candles (%s time)%s", sub("\\.NS$", "", input$ltick),
      if (input$lmk == "NSE") "IST" else "New York", if (isTRUE(lv$n_active > 0)) "; the last candle is still forming" else "")
  })
  output$lcandle <- renderPlotly({
    b <- lsession(); x <- b[b$ticker == input$ltick, ]; x <- x[order(x$bucket), ]
    validate(need(nrow(x) > 1, "Waiting for intraday data."))
    t <- format(x$bucket, "%Y-%m-%d %H:%M", tz = LIVE$sessions[[input$lmk]]$tz)
    vol <- ifelse(is.finite(x$volume), x$volume, 0)
    cv <- cumsum(vol)
    vwap <- ifelse(cv > 0, cumsum((x$high + x$low + x$close) / 3 * vol) / cv, NA)   # undefined before the first trade
    p1 <- plot_ly(x = t, type = "candlestick", open = x$open, high = x$high, low = x$low, close = x$close, name = "Price",
                  increasing = list(line = list(color = UP)), decreasing = list(line = list(color = DOWN))) |>
      add_lines(x = t, y = vwap, name = "VWAP", line = list(color = "#2a78d6", width = 1.5), inherit = FALSE)
    p2 <- plot_ly(x = t, y = vol, type = "bar", name = "Volume", marker = list(color = ifelse(x$close >= x$open, UP, DOWN)))
    subplot(p1, p2, nrows = 2, heights = c(0.76, 0.24), shareX = TRUE, titleY = TRUE) |>
      layout(xaxis = list(rangeslider = list(visible = FALSE), type = "date"), xaxis2 = list(type = "date"),
             yaxis = list(title = "Price", range = range(c(x$low, x$high)) + c(-1, 1) * 0.05 * diff(range(c(x$low, x$high)))),
             yaxis2 = list(title = "Volume"),
             legend = list(orientation = "h", y = 1.06), hovermode = "x unified", margin = list(t = 30)) |>
      config(displaylogo = FALSE)
  })
  output$lnet_title <- renderText({ g <- lgraph(); if (is.null(g)) return("Live correlation graph")
    sprintf("Live correlation graph: last %d one-minute returns, QSW at ω = %.2f", g$n_bars, input$lomega) })
  output$lnet <- renderVisNetwork({
    g <- lgraph(); w <- lwalk(); ch <- lchg()[g$tick]; rv <- lrv()[g$tick]
    ramp <- grDevices::colorRamp(c(DOWN, FLAT, UP)); z <- pmin(pmax((ch + 0.03) / 0.06, 0), 1)
    col <- grDevices::rgb(ramp(ifelse(is.finite(z), z, 0.5)), maxColorValue = 255)
    nodes <- data.frame(id = g$tick, label = sub("\\.NS$", "", g$tick), color = col, value = 10 + 100 * rv / max(rv),
      title = sprintf("%s<br>change %s<br>intraday vol %s<br>QSW spillover %s<br>return prob. %.3f",
                      g$tick, pct(ch, 2), pct(rv), pct(w$q_volspill), w$q_self),
      borderWidth = ifelse(g$tick %in% input$ltick, 4, 1))
    idx <- which(g$adj == 1 & upper.tri(g$adj), arr.ind = TRUE)
    edges <- data.frame(from = g$tick[idx[, 1]], to = g$tick[idx[, 2]], width = 1 + 4 * pmax(g$rho[idx], 0),
                        title = sprintf("ρ = %.2f", g$rho[idx]), color = "#b9b8b3")
    visNetwork(nodes, edges) |> visPhysics(stabilization = list(iterations = 150)) |>
      visOptions(highlightNearest = TRUE) |> visInteraction(navigationButtons = TRUE)
  })
  output$ltable <- renderDT({
    b <- lsession(); last <- tapply(b$close[order(b$bucket)], b$ticker[order(b$bucket)], function(v) tail(v, 1))
    tk <- names(last); w <- lwalk(); f <- lforecast(); ch <- lchg()
    d <- data.frame(Stock = sub("\\.NS$", "", tk), Last = round(as.numeric(last), 2),
      `Change %` = round(100 * as.numeric(ch[tk]), 2), `Intraday vol %` = round(100 * as.numeric(lrv()[tk]), 1),
      `QSW spillover %` = round(100 * w$q_volspill[match(tk, w$ticker)], 1),
      `Return prob.` = round(w$q_self[match(tk, w$ticker)], 3),
      `GHAR 5-day vol %` = if (is.null(f)) NA else round(100 * f$vol5_ann[match(tk, f$ticker)], 1), check.names = FALSE)
    datatable(d[order(-d$`Intraday vol %`), ], rownames = FALSE, options = list(pageLength = 20, dom = "t", scrollX = TRUE))
  })
  output$lstore <- renderText({
    invalidateLater(15000)
    n <- DBI::dbGetQuery(store_con, "SELECT COUNT(*) n, COUNT(DISTINCT ticker) t, MIN(bucket_start) a, MAX(bucket_start) b FROM candles WHERE interval_sec = 60")
    rng <- if (is.na(n$a)) "" else paste(format(as.POSIXct(c(n$a, n$b), origin = "1970-01-01"), "%Y-%m-%d %H:%M"), collapse = " to ")
    paste0(sprintf("%s candles for %d tickers in %s (%s)\n", format(n$n, big.mark = ","), n$t,
                   if (identical(getOption("qstock.live_db"), ":memory:")) "memory" else LIVE$db_path, rng),
           sprintf("last poll: %s written, %s rejected; %d errors; fetch %.2f s (range %s)",
                   lv$store[["written"]], lv$store[["rejected"]], length(lv$errors), lv$fetch_sec, lv$range))
  })

  g <- reactive({ req(input$mk, input$dt); graph_on(input$mk, as.Date(input$dt)) })
  output$start_ui <- renderUI({ tk <- g()$tick; selectInput("start", "Start stock", tk, selected = if ("NVDA" %in% tk) "NVDA" else tk[1]) })
  output$graph_title <- renderText(sprintf("%s kNN correlation graph on %s (k = %d)", input$mk, format(g()$date), QS$knn_k))
  dist <- reactive({
    req(input$start); gg <- g(); i <- match(input$start, gg$tick); req(!is.na(i))
    one <- function(om) { Pm <- qsw_distributions(gg$w, om, taus); pmax(Pm[i, ], 0) / sum(pmax(Pm[i, ], 0)) }
    data.frame(ticker = gg$tick, sel = one(input$omega), ctqw = one(0), classical = one(1))
  })
  output$net <- renderVisNetwork({
    gg <- g(); d <- dist()
    idx <- which(gg$adj == 1 & upper.tri(gg$adj), arr.ind = TRUE)
    nodes <- data.frame(id = gg$tick, label = sub("\\.NS$", "", gg$tick),
                        value = 5 + 200 * d$sel, title = sprintf("%s: p = %.3f", gg$tick, d$sel),
                        color = ifelse(gg$tick == input$start, PAL[["ctqw"]], PAL[["sel"]]))
    edges <- data.frame(from = gg$tick[idx[, 1]], to = gg$tick[idx[, 2]],
                        width = 1 + 4 * pmax(gg$rho[idx], 0), title = sprintf("ρ = %.2f", gg$rho[idx]), color = "#b9b8b3")
    visNetwork(nodes, edges) |> visPhysics(stabilization = list(iterations = 150)) |>
      visOptions(highlightNearest = TRUE) |> visInteraction(navigationButtons = TRUE)
  })
  output$bars <- renderPlot({
    d <- dist(); d <- d[order(-d$classical), ]
    long <- rbind(data.frame(ticker = d$ticker, series = sprintf("ω = %.2f (selected)", input$omega), p = d$sel),
                  data.frame(ticker = d$ticker, series = "ω = 0 (CTQW)", p = d$ctqw),
                  data.frame(ticker = d$ticker, series = "ω = 1 (classical)", p = d$classical))
    long$ticker <- factor(sub("\\.NS$", "", long$ticker), levels = sub("\\.NS$", "", d$ticker))
    ggplot(long, aes(ticker, p, fill = series)) + geom_col(position = position_dodge(width = 0.8), width = 0.75) +
      scale_fill_manual(values = unname(PAL[c("sel", "ctqw", "classical")]), name = NULL) +
      labs(x = NULL, y = "Time-averaged probability") + theme_app +
      theme(axis.text.x = element_text(angle = 60, hjust = 1))
  })
  output$walkstats <- renderTable({
    d <- dist(); i <- match(input$start, d$ticker)
    ent <- function(p) -sum(ifelse(p > 0, p * log(p), 0))
    data.frame(Walk = c(sprintf("ω = %.2f", input$omega), "ω = 0 (CTQW)", "ω = 1 (classical)"),
               `Return probability` = c(d$sel[i], d$ctqw[i], d$classical[i]),
               Entropy = c(ent(d$sel), ent(d$ctqw), ent(d$classical)), check.names = FALSE)
  }, digits = 4)

  output$ftick_ui <- renderUI({ tk <- sort(unique(prices$ticker[prices$market == input$fmk]))
    selectInput("ftick", "Stock", tk, selected = if ("NVDA" %in% tk) "NVDA" else tk[1]) })
  fdat <- reactive({
    req(input$ftick)
    parts <- list(HAR = "baseline", `QSW ω=0.25` = "qsw_w025", `QSW ω=1 (classical)` = "qsw_w100")
    d <- do.call(rbind, lapply(names(parts), function(nm) { x <- load_pred(input$fmk, parts[[nm]]); if (is.null(x)) return(NULL)
      x <- x[x$ticker == input$ftick & x$date >= input$frange[1] & x$date <= input$frange[2], ]; if (!nrow(x)) return(NULL); x$model <- nm; x }))
    validate(need(!is.null(d) && nrow(d) > 0, "No saved forecasts for this selection (run scripts/11_v2_experiments.R)."))
    d
  })
  output$fplot <- renderPlot({
    d <- fdat(); real <- unique(d[, c("date", "y")])
    ggplot() + geom_line(data = real, aes(date, y), colour = "#8a8984", linewidth = 0.4) +
      geom_line(data = d, aes(date, pred, colour = model), linewidth = 0.7) +
      scale_colour_manual(values = c("HAR" = PAL[["ctqw"]], "QSW ω=0.25" = PAL[["sel"]], "QSW ω=1 (classical)" = PAL[["classical"]]), name = NULL) +
      labs(x = NULL, y = "log 5-day mean squared return", caption = "Grey: realised. Forecasts are out-of-sample (monthly walk-forward).") + theme_app
  })
  output$ftable <- renderTable({
    d <- fdat(); a <- aggregate(cbind(mse = (y - pred)^2, qlike = qlike(y, pred)) ~ model, d, mean); a
  }, digits = 4)

  dt <- function(f, ...) renderDT({ x <- rd(f); validate(need(!is.null(x), paste("Not yet produced:", f)))
    num <- vapply(x, is.numeric, TRUE); x[num] <- lapply(x[num], signif, 4); datatable(x, options = list(pageLength = 15, scrollX = TRUE), rownames = FALSE, ...) })
  output$t_h <- dt("results/tables/v2_hypothesis_tests.csv")
  output$t_ghar <- dt("results/tables/v2_ghar_pairwise.csv")
  output$t_mcs <- dt("results/tables/v2_mcs.csv")
  output$t_rob <- dt("results/tables/v2_robustness_tickers.csv")
  output$t_pow <- dt("results/tables/power_analysis_summary.csv")
  output$t_v1 <- dt("results/tables/experiment_results.csv")
  output$figs <- renderUI({
    fs <- sort(list.files(P("results", "figures"), pattern = "\\.png$"))
    tagList(lapply(fs, function(f) tags$div(tags$h5(f), tags$img(src = file.path("figs", f), style = "max-width:100%;margin-bottom:24px;"))))
  })
  txt <- function(f, n = 40) renderText({ if (file.exists(P(f))) paste(tail(readLines(P(f), warn = FALSE), n), collapse = "\n") else paste("Not yet produced:", f) })
  output$hadoop_log <- txt("results/stage3_hadoop_hive_log.txt", 30)
  output$spark_log <- txt("results/stage3_spark_log.txt", 10)
  output$spark_tbl <- renderTable(rd("results/tables/spark_scaling.csv"), digits = 3)
  output$scal_tbl <- renderTable(rd("results/tables/qw_scalability.csv"), digits = 4)
  output$gpu_tbl <- renderTable({ x <- rd("results/tables/gpu_benchmark.csv"); validate(need(!is.null(x), "GPU benchmark not yet run.")); x }, digits = 4)
  output$health <- renderPlot({
    x <- rd("results/system_monitor.csv"); validate(need(!is.null(x) && nrow(x) > 1, "No health log yet."))
    x$time <- as.POSIXct(x$time, format = "%Y-%m-%dT%H:%M:%S")
    long <- rbind(data.frame(time = x$time, metric = "CPU clock, % of max (<60 = throttling)", value = x$cpu_perf_pct_of_max),
                  data.frame(time = x$time, metric = "GPU temperature, °C (guard trips at 87)", value = x$gpu_temp_c))
    ggplot(long, aes(time, value)) + geom_line(colour = PAL[["sel"]], linewidth = 0.6) +
      facet_wrap(~metric, scales = "free_y", ncol = 1) + labs(x = NULL, y = NULL) + theme_app
  })
  output$guard <- renderText({
    f <- P("results", "thermal_guard.log"); if (!file.exists(f)) return("Guard not started.")
    con <- file(f, encoding = "UTF-16LE"); on.exit(close(con)); paste(readLines(con, warn = FALSE), collapse = "\n")
  })
}

shinyApp(ui, server)
