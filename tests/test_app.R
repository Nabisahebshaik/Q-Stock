# Headless test of the Shiny dashboard's server logic (run from the project root):
#   Rscript tests/test_app.R
library(shiny)
app <- shinyAppDir("app")
testServer(app, {
  session$setInputs(mk = "NASDAQ", dt = as.Date("2026-10-20"))
  session$setInputs(start = "NVDA", omega = 0.25)
  d <- dist()
  stopifnot(nrow(d) == 20, abs(sum(d$sel) - 1) < 1e-8, abs(sum(d$classical) - 1) < 1e-8)
  stopifnot(any(abs(d$sel - d$classical) > 1e-4))           # dial actually changes the walk
  session$setInputs(omega = 1)
  stopifnot(max(abs(dist()$sel - dist()$classical)) < 1e-10) # omega = 1 equals the classical limit
  session$setInputs(fmk = "NASDAQ", ftick = "NVDA", frange = c(as.Date("2025-01-01"), as.Date("2026-10-20")))
  stopifnot(nrow(fdat()) > 100)
  cat("dashboard server tests passed: walk mass =", sum(d$sel), "; forecast rows =", nrow(fdat()), "\n")
})
