USE qstock;

-- R1: ranking of feature sets by out-of-sample AUC within each market and model
SELECT 'R1' AS q, market, model, feature_set, ROUND(auc, 4) AS auc, ROUND(f1, 4) AS f1,
       ROUND(sharpe_net, 3) AS sharpe_net, ROUND(dm_p_vs_classical, 4) AS dm_p, rk
FROM (SELECT *, RANK() OVER (PARTITION BY market, model ORDER BY auc DESC) AS rk
      FROM experiment_results WHERE experiment = 'main') t
ORDER BY market, model, rk;

-- R2: yearly out-of-sample accuracy of the DTQW+CTQW fusion feature set
SELECT 'R2' AS q, market, model, SUBSTR(fold, 1, 4) AS yr,
       ROUND(AVG(CASE WHEN (p_up > 0.5) = (y_up = 1) THEN 1.0 ELSE 0.0 END), 4) AS accuracy,
       COUNT(*) AS n
FROM predictions
WHERE feature_set = 'classical_fusion'
GROUP BY market, model, SUBSTR(fold, 1, 4)
ORDER BY market, model, yr;

-- R3: number of prediction rows stored per experiment and model
SELECT 'R3' AS q, experiment, model, COUNT(*) AS n_predictions
FROM predictions GROUP BY experiment, model;
