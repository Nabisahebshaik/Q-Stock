# Q-Stock interactive dashboard (R Shiny).
# Run from the project root:  Rscript -e "shiny::runApp('app', port = 8050, launch.browser = TRUE)"
# All quantum walks are classical simulations; the "Quantum dial" tab integrates the
# Lindblad equation live (R/qsw.R) on the selected day's real correlation graph.

suppressPackageStartupMessages({ library(shiny); library(bslib); library(visNetwork); library(DT); library(ggplot2) })
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

# ---- UI ----
ui <- page_navbar(
  title = "Q-Stock", theme = bs_theme(version = 5, bootswatch = "flatly"),
  nav_panel("Overview",
    layout_columns(col_widths = c(12),
      card(card_header("What this project is"),
        p("A leakage-controlled Big Data framework that tests whether ", strong("quantum coherence"),
          " in walks on daily stock-correlation graphs helps forecasting (NSE + NASDAQ, 2015-2026)."),
        p("All quantum walks are ", strong("classical simulations"), " (no quantum hardware). Pipeline: Yahoo + GDELT → HDFS (WebHDFS) → ",
          "Hadoop MapReduce (Java) → Hive → Spark (sparklyr) → R models (walk-forward, pre-registered tests) → this dashboard."),
        uiOutput("headline")))),
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
