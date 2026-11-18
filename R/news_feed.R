# Company news headlines for the dashboard (viewing only: like live prices, they never
# enter the research datasets; the research sentiment features are R/sentiment_gdelt.R).
#
# Source 1: Yahoo Finance search endpoint (same unofficial host as the price charts) -
#           headline, publisher, link and publication time per article.
# Source 2: GDELT DOC 2.0 article list, used only when Yahoo returns nothing.
# No headline is ever generated or filled in: an empty or failed feed is reported as such.

yahoo_news_url <- function(symbol, n = 12)
  sprintf("https://query1.finance.yahoo.com/v1/finance/search?q=%s&quotesCount=0&newsCount=%d&enableFuzzyQuery=false",
          utils::URLencode(symbol, reserved = TRUE), n)

parse_yahoo_news <- function(json_text, symbol) {
  j <- jsonlite::fromJSON(json_text, simplifyVector = FALSE)
  items <- j$news
  if (!length(items)) return(news_empty())
  data.frame(
    id = vapply(items, function(x) as.character(x$uuid %||% x$link %||% NA), ""),
    title = vapply(items, function(x) as.character(x$title %||% NA), ""),
    publisher = vapply(items, function(x) as.character(x$publisher %||% NA), ""),
    url = vapply(items, function(x) as.character(x$link %||% NA), ""),
    published = vapply(items, function(x) as.numeric(x$providerPublishTime %||% NA), 0),
    related = vapply(items, function(x) paste(unlist(x$relatedTickers), collapse = ","), ""),
    source = "yahoo", stringsAsFactors = FALSE)
}

news_empty <- function() data.frame(id = character(), title = character(), publisher = character(), url = character(),
                                     published = numeric(), related = character(), source = character())

gdelt_artlist_url <- function(query, days = 7, n = 15)
  paste0("https://api.gdeltproject.org/api/v2/doc/doc?query=", utils::URLencode(query, reserved = TRUE),
         "&mode=artlist&format=json&sort=datedesc&maxrecords=", n, "&timespan=", days, "d")

parse_gdelt_artlist <- function(json_text, symbol) {
  if (!startsWith(trimws(json_text), "{")) return(news_empty())
  a <- jsonlite::fromJSON(json_text, simplifyVector = FALSE)$articles
  if (!length(a)) return(news_empty())
  t <- vapply(a, function(x) as.character(x$seendate %||% NA), "")
  data.frame(id = vapply(a, function(x) as.character(x$url %||% NA), ""),
             title = vapply(a, function(x) as.character(x$title %||% NA), ""),
             publisher = vapply(a, function(x) as.character(x$domain %||% NA), ""),
             url = vapply(a, function(x) as.character(x$url %||% NA), ""),
             published = as.numeric(as.POSIXct(t, format = "%Y%m%dT%H%M%SZ", tz = "UTC")),
             related = symbol, source = "gdelt", stringsAsFactors = FALSE)
}

http_text <- function(url, timeout = 15) {
  r <- curl::curl_fetch_memory(url, handle = curl::new_handle(useragent = "Mozilla/5.0", timeout = timeout))
  if (r$status_code != 200) stop("HTTP ", r$status_code)
  rawToChar(r$content)
}

# Default fetcher: Yahoo first, GDELT if Yahoo fails or is empty. Returns list(items, errors).
fetch_news <- function(symbol, name, n = 12) {
  errs <- character()
  y <- tryCatch(parse_yahoo_news(http_text(yahoo_news_url(symbol, n)), symbol),
                error = function(e) { errs[["yahoo"]] <<- conditionMessage(e); news_empty() })
  if (nrow(y)) return(list(items = y, errors = errs))
  g <- tryCatch(parse_gdelt_artlist(http_text(gdelt_artlist_url(sentiment_query(symbol, name), n = n)), symbol),
                error = function(e) { errs[["gdelt"]] <<- conditionMessage(e); news_empty() })
  list(items = g, errors = errs)
}

# Newest first, duplicates (same title) dropped, at most n.
news_clean <- function(items, n = 12) {
  items <- items[!is.na(items$title) & nzchar(items$title) & !is.na(items$url), ]
  items <- items[order(-items$published), ]
  items <- items[!duplicated(tolower(items$title)), ]
  utils::head(items, n)
}
