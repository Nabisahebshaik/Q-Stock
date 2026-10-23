-- Q-Stock Hive tables over HDFS (Hive 1.1, CDH 5.13). External tables: dropping
-- a table never deletes the HDFS data.
CREATE DATABASE IF NOT EXISTS qstock;
USE qstock;

DROP TABLE IF EXISTS prices;
CREATE EXTERNAL TABLE prices (
  market STRING, ticker STRING, dt STRING,
  open DOUBLE, high DOUBLE, low DOUBLE, close DOUBLE, volume DOUBLE, log_ret DOUBLE)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/user/cloudera/qstock/curated/prices'
TBLPROPERTIES ('skip.header.line.count' = '1');

DROP TABLE IF EXISTS mr_monthly_stats;
CREATE EXTERNAL TABLE mr_monthly_stats (
  market STRING, ticker STRING, month STRING, n_days INT, month_log_ret DOUBLE,
  mean_log_ret DOUBLE, realized_vol_ann DOUBLE, total_volume BIGINT)
ROW FORMAT DELIMITED FIELDS TERMINATED BY '\t'
STORED AS TEXTFILE
LOCATION '/user/cloudera/qstock/mr/monthly_stats';

DROP TABLE IF EXISTS sentiment_daily;
-- OpenCSVSerde (handles the quoted query strings) exposes every column as STRING.
CREATE EXTERNAL TABLE sentiment_daily (
  day STRING, n_articles STRING, tone STRING, ticker STRING, query STRING)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
STORED AS TEXTFILE
LOCATION '/user/cloudera/qstock/raw/sentiment'
TBLPROPERTIES ('skip.header.line.count' = '1');
