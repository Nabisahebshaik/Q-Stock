# Sign-in, explainable forecast, news parsing, Kotak Neo adapter and the assistant.
# Offline: fixtures follow the documented response shapes; no network access.

test_that("accounts: scrypt hash round-trip, file has no password, bad input rejected", {
  p <- tempfile(fileext = ".json")
  u <- auth_add_user("Nabi", "correct horse battery", path = p)
  expect_equal(u$username, "Nabi")
  txt <- paste(readLines(p), collapse = "")
  expect_false(grepl("correct horse", txt, fixed = TRUE))
  us <- auth_read_users(p, env = "")
  expect_true(sodium::password_verify(us$nabi$hash, "correct horse battery"))
  expect_error(auth_add_user("Nabi", "short", path = p), "8 characters")
  expect_error(auth_add_user("1bad name", "long enough pw", path = p), "user name")
  expect_equal(names(auth_read_users(p, env = jsonlite::toJSON(list(list(username = "X", hash = "h")), auto_unbox = TRUE))), "x")
})

test_that("sessions: login, token lookup, expiry, logout and lock-out", {
  p <- tempfile(fileext = ".json"); auth_add_user("Nabi", "correct horse battery", path = p)
  st <- auth_store(auth_read_users(p, env = ""))
  expect_true(auth_enabled(st)); expect_false(auth_enabled(auth_store(list())))
  bad <- auth_login(st, "nabi", "wrong password")
  expect_false(bad$ok); expect_equal(bad$status, 401)
  ok <- auth_login(st, "NABI", "correct horse battery")            # user name is case-insensitive
  expect_true(ok$ok); expect_equal(nchar(ok$token), 64); expect_equal(ok$user$display_name, "Nabi")
  expect_null(ok$user$hash)
  expect_equal(auth_user(st, ok$token)$username, "Nabi")
  expect_null(auth_user(st, ok$token, now = Sys.time() + 13 * 3600))  # expired and removed
  expect_null(auth_user(st, ok$token))
  t2 <- auth_login(st, "nabi", "correct horse battery")$token
  auth_logout(st, t2); expect_null(auth_user(st, t2))
  for (i in 1:5) auth_login(st, "nabi", "nope")
  lk <- auth_login(st, "nabi", "correct horse battery")
  expect_false(lk$ok); expect_equal(lk$status, 429)                # locked even with the right password
  expect_true(auth_login(st, "nabi", "correct horse battery", now = Sys.time() + 11 * 60)$ok)
  expect_equal(auth_token_of(list(HTTP_AUTHORIZATION = "Bearer abc")), "abc")
  expect_equal(auth_token_of(list()), "")
})

fake_forecast <- function() {
  set.seed(3); X <- data.frame(ticker = c("A.NS", "B.NS", "C.NS", "D.NS"), matrix(rnorm(24, -8, 1), 4, dimnames = list(NULL, GHAR_COLS)))
  b <- c(-3, 0.01, 0.02, 0.17, 0.03, 0.03, 0.4)
  pred <- as.numeric(cbind(1, as.matrix(X[, GHAR_COLS])) %*% b)
  f <- data.frame(ticker = X$ticker, as_of = as.Date("2026-11-17"), pred_lrv5 = pred, vol5_ann = sqrt(exp(pred) * 252))
  attr(f, "features") <- X
  list(f = f, b = b)
}

test_that("explanation is exact: contributions sum to forecast minus the market average", {
  z <- fake_forecast()
  for (tk in z$f$ticker) {
    e <- explain_forecast(z$f, z$b, tk)
    expect_equal(sum(e$features$contribution), e$pred_lrv5 - e$baseline_lrv5, tolerance = 1e-12)
    expect_equal(e$baseline_lrv5, mean(z$f$pred_lrv5), tolerance = 1e-12)
    expect_equal(prod(e$features$vol_factor) * e$baseline_vol5_ann, e$vol5_ann, tolerance = 1e-10)
    expect_equal(sum(e$groups$contribution), sum(e$features$contribution), tolerance = 1e-12)
    expect_true(all(diff(abs(e$features$contribution)) <= 0))   # sorted by size
  }
  expect_null(explain_forecast(z$f, z$b, "ZZZ"))
  expect_match(explain_forecast(z$f, z$b, "A.NS")$summary, "^A: forecast 5-day volatility")
})

test_that("news parsers: Yahoo search and GDELT article list; cleaning drops blanks and duplicates", {
  y <- jsonlite::toJSON(list(news = list(
    list(uuid = "1", title = "Reliance Q2 results", publisher = "Reuters", link = "https://x/1", providerPublishTime = 1763400000, relatedTickers = list("RELIANCE.NS")),
    list(uuid = "2", title = "reliance q2 results", publisher = "Mint", link = "https://x/2", providerPublishTime = 1763390000),
    list(uuid = "3", title = "Older story", publisher = "ET", link = "https://x/3", providerPublishTime = 1763300000))), auto_unbox = TRUE)
  d <- parse_yahoo_news(y, "RELIANCE.NS")
  expect_equal(nrow(d), 3); expect_equal(d$publisher[1], "Reuters"); expect_equal(d$related[1], "RELIANCE.NS")
  cl <- news_clean(d)
  expect_equal(cl$id, c("1", "3"))
  expect_equal(nrow(parse_yahoo_news('{"news": []}', "X")), 0)
  g <- jsonlite::toJSON(list(articles = list(list(url = "https://g/1", title = "TCS wins deal", domain = "livemint.com", seendate = "20261117T101500Z"))), auto_unbox = TRUE)
  gd <- parse_gdelt_artlist(g, "TCS.NS")
  expect_equal(gd$publisher, "livemint.com"); expect_equal(gd$published, as.numeric(as.POSIXct("2026-11-17 10:15:00", tz = "UTC")))
  expect_equal(nrow(parse_gdelt_artlist("Please limit requests", "X")), 0)
})

test_that("TOTP matches RFC 6238 test vectors (SHA-1)", {
  skip_if_not(requireNamespace("openssl", quietly = TRUE) || requireNamespace("digest", quietly = TRUE))
  key <- charToRaw("12345678901234567890")
  expect_equal(totp(time = 59, digits = 8, key = key), "94287082")
  expect_equal(totp(time = 1111111109, digits = 8, key = key), "07081804")
  expect_equal(totp(time = 2000000000, digits = 8, key = key), "69279037")
  expect_equal(base32_decode("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"), key)
})

test_that("Kotak Neo parsers: historical candles and quotes", {
  j <- jsonlite::fromJSON('{"status":"success","interval":"1min","data":{"candles":[
        ["2026-11-17T09:15:00+0530",1320.0,1322.5,1319.0,1321.0,15000,0],
        ["2026-11-17T09:16:00+0530",1321.0,1321.5,1320.0,1320.5,9000,0]]}}', simplifyVector = FALSE)
  d <- parse_kotak_candles(j, "RELIANCE.NS")
  expect_equal(nrow(d), 2); expect_equal(d$close, c(1321, 1320.5))
  expect_equal(as.numeric(d$ts[1]), as.numeric(as.POSIXct("2026-11-17 03:45:00", tz = "UTC")))
  q <- jsonlite::fromJSON('[{"exchange_token":"2885","ltp":"1320.5","change":"-4.5","lstup_time":"1763371000","ohlc":{"open":"1320","high":"1322.5","low":"1319","close":"1325"}}]', simplifyVector = FALSE)
  m <- parse_kotak_quotes(q, c(RELIANCE.NS = "2885"))
  expect_equal(m$RELIANCE.NS$prev_close, 1325); expect_equal(m$RELIANCE.NS$price, 1320.5)
  expect_null(parse_kotak_candles(list(data = list(candles = list())), "X"))
})

test_that("live fetcher: Yahoo only when Kotak is not configured; feed recorded per symbol", {
  withr_env <- Sys.getenv("KOTAK_ACCESS_TOKEN"); Sys.unsetenv("KOTAK_ACCESS_TOKEN"); on.exit(Sys.setenv(KOTAK_ACCESS_TOKEN = withr_env))
  expect_false(kotak_configured())
  orig <- fetch_intraday_many
  assign("fetch_intraday_many", function(symbols, interval, range) list(data = setNames(lapply(symbols, function(s) data.frame(ticker = s)), symbols), errors = character()), globalenv())
  on.exit(assign("fetch_intraday_many", orig, globalenv()), add = TRUE)
  r <- fetch_intraday_auto(c("TCS.NS", "AAPL"))
  expect_equal(unname(r$source[c("TCS.NS", "AAPL")]), c("yahoo", "yahoo"))
})

test_that("assistant: ticker and intent detection", {
  expect_equal(assistant_find_ticker("why is reliance so volatile?")$ticker, "RELIANCE.NS")
  expect_equal(assistant_find_ticker("explain NVDA")$ticker, "NVDA")
  expect_equal(assistant_find_ticker("news on Apple please")$ticker, "AAPL")
  expect_equal(assistant_find_ticker("Tata Consultancy Services price")$ticker, "TCS.NS")
  expect_null(assistant_find_ticker("hello there"))
  expect_equal(assistant_intent("Why is INFY's forecast high?"), "explain")
  expect_equal(assistant_intent("should I buy TCS"), "advice")
  expect_equal(assistant_intent("what does the omega dial do"), "quantum")
  expect_equal(assistant_intent("did the quantum features beat the baseline"), "results")
  expect_equal(assistant_intent("latest headlines for AAPL"), "news")
})

test_that("assistant replies are grounded and say when data are missing", {
  z <- fake_forecast(); z$f$ticker <- c("RELIANCE.NS", "TCS.NS", "INFY.NS", "SBIN.NS"); attr(z$f, "features")$ticker <- z$f$ticker
  tabs <- function(f) { p <- file.path("results", "tables", f); if (file.exists(p)) read.csv(p) else NULL }
  ctx <- list(forecast = function(mk) z$f, explain = function(mk, tk) explain_forecast(z$f, z$b, tk),
              live = function(mk) NULL, news = function(mk, tk) list(items = news_empty(), errors = c(yahoo = "HTTP 429")), table = tabs)
  r <- assistant_reply("why is reliance's volatility high?", ctx)
  expect_equal(r$intent, "explain"); expect_match(r$reply, "exact for the linear model"); expect_true("R/explain.R" %in% unlist(r$sources))
  f <- assistant_reply("forecast for TCS", ctx)
  expect_match(f$reply, sprintf("%.1f%%", 100 * z$f$vol5_ann[2]), fixed = TRUE)
  expect_match(assistant_reply("should I buy INFY?", ctx)$reply, "can't tell you whether to buy")
  expect_match(assistant_reply("news on SBIN", ctx)$reply, "No news found for SBIN.*feed failed")
  expect_match(assistant_reply("price of SBIN", ctx)$reply, "No live quote")
  ctx$forecast <- function(mk) NULL
  expect_match(assistant_reply("forecast for TCS", ctx)$reply, "not available")
  expect_equal(assistant_reply("blorp", ctx)$intent, "unknown")
  if (file.exists("results/tables/v2_hypothesis_tests.csv"))
    expect_match(assistant_reply("did the quantum features beat the baseline?", ctx)$reply, "NASDAQ, MSE loss")
})
