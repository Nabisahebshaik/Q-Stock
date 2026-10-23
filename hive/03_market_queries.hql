USE qstock;

-- Q1: coverage per market
SELECT 'Q1' AS q, market, COUNT(*) AS n_rows, COUNT(DISTINCT ticker) AS n_tickers,
       MIN(dt) AS first_day, MAX(dt) AS last_day
FROM prices GROUP BY market;

-- Q2: average monthly realised volatility per market and year (from the MapReduce output)
SELECT 'Q2' AS q, market, SUBSTR(month, 1, 4) AS yr,
       ROUND(AVG(realized_vol_ann), 4) AS avg_vol_ann, COUNT(*) AS ticker_months
FROM mr_monthly_stats
GROUP BY market, SUBSTR(month, 1, 4)
ORDER BY market, yr;

-- Q3: the five most volatile ticker-months per market (windowing)
SELECT 'Q3' AS q, market, ticker, month, ROUND(realized_vol_ann, 4) AS vol_ann, rk
FROM (SELECT market, ticker, month, realized_vol_ann,
             ROW_NUMBER() OVER (PARTITION BY market ORDER BY realized_vol_ann DESC) AS rk
      FROM mr_monthly_stats) t
WHERE rk <= 5
ORDER BY market, rk;

-- Q4: consistency check, MapReduce day counts vs raw rows (expect zero rows)
SELECT 'Q4' AS q, p.ticker, p.n AS rows_in_prices, m.n AS days_in_mr
FROM (SELECT ticker, COUNT(log_ret) AS n FROM prices GROUP BY ticker) p
JOIN (SELECT ticker, SUM(n_days) AS n FROM mr_monthly_stats GROUP BY ticker) m
  ON p.ticker = m.ticker
WHERE p.n <> m.n;

-- Q5: news coverage per ticker (GDELT article counts)
SELECT 'Q5' AS q, ticker, SUM(CAST(n_articles AS BIGINT)) AS articles,
       SUM(CASE WHEN CAST(n_articles AS INT) > 0 THEN 1 ELSE 0 END) AS days_with_news
FROM sentiment_daily GROUP BY ticker ORDER BY articles DESC;
