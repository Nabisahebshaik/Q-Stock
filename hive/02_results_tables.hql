USE qstock;

DROP TABLE IF EXISTS experiment_results;
CREATE EXTERNAL TABLE experiment_results (
  experiment STRING, market STRING, model STRING, feature_set STRING,
  n BIGINT, accuracy DOUBLE, f1 DOUBLE, mcc DOUBLE, auc DOUBLE, logloss DOUBLE,
  sharpe_net DOUBLE, sharpe_gross DOUBLE, sharpe_buyhold DOUBLE,
  ann_return_net DOUBLE, ann_vol_net DOUBLE, max_drawdown_net DOUBLE,
  avg_exposure DOUBLE, turnover_cost_ann DOUBLE,
  dm_stat_vs_classical DOUBLE, dm_p_vs_classical DOUBLE)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/user/cloudera/qstock/results/experiments'
TBLPROPERTIES ('skip.header.line.count' = '1');

DROP TABLE IF EXISTS predictions;
CREATE EXTERNAL TABLE predictions (
  experiment STRING, model STRING, feature_set STRING, fold STRING, dt STRING,
  ticker STRING, market STRING, p_up DOUBLE, y_up INT, next_ret DOUBLE)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
STORED AS TEXTFILE
LOCATION '/user/cloudera/qstock/results/predictions'
TBLPROPERTIES ('skip.header.line.count' = '1');
