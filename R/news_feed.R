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

# Default fetcher: Yahoo by symbol; Yahoo by company name when the symbol has no news (common
# for NSE ".NS" symbols), keeping only headlines that name the company; GDELT last.
# Returns list(items, errors).
fetch_news <- function(symbol, name, n = 12) {
  errs <- character()
  try_src <- function(src, expr) tryCatch(expr, error = function(e) { errs[[src]] <<- conditionMessage(e); news_empty() })
  y <- try_src("yahoo", parse_yahoo_news(http_text(yahoo_news_url(symbol, n)), symbol))
  if (nrow(y)) return(list(items = y, errors = errs))
  if (!is.null(name) && !is.na(name) && nzchar(name)) {
    q <- sub(" (Ltd|Limited|Inc|Corp|Corporation|Industries Ltd)\\.?$", "", name)
    yn <- try_src("yahoo_name", parse_yahoo_news(http_text(yahoo_news_url(q, n)), symbol))
    yn <- news_about(yn, symbol, name)
    if (nrow(yn)) return(list(items = yn, errors = errs))
  }
  g <- try_src("gdelt", parse_gdelt_artlist(http_text(gdelt_artlist_url(sentiment_query(symbol, name), n = n), timeout = 30), symbol))
  list(items = g, errors = errs)
}

# Keeps headlines that are about the company: the title names it (symbol or a distinctive
# word of its name) or Yahoo tags the article with the symbol.
news_about <- function(items, symbol, name) {
  if (!nrow(items)) return(items)
  label <- sub("\\.NS$", "", symbol)
  words <- tolower(strsplit(gsub("[^A-Za-z& ]", " ", name), " +")[[1]])
  words <- words[nchar(words) > 3 & !words %in% c("ltd", "limited", "india", "industries", "bank", "services", "corporation", "company", "the")]
  pat <- paste0("\\b(", paste(c(tolower(label), words), collapse = "|"), ")\\b")
  keep <- grepl(pat, tolower(items$title), perl = TRUE) | grepl(symbol, items$related, fixed = TRUE)
  items[keep, ]
}

# Newest first, duplicates (same title) dropped, at most n.
news_clean <- function(items, n = 12) {
  items <- items[!is.na(items$title) & nzchar(items$title) & !is.na(items$url), ]
  items <- items[order(-items$published), ]
  items <- items[!duplicated(tolower(items$title)), ]
  utils::head(items, n)
}
