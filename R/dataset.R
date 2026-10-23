# Assemble the modelling dataset: classical + graph-walk + regime (+ sentiment).

# Market-level volatility regime, past-only: 1 if the cross-sectional mean of
# vol_20 at t exceeds its own median over the previous 250 trading days.
add_regime <- function(df) {
  out <- lapply(split(df, df$market), function(d) {
    mv <- aggregate(vol_20 ~ date, d, mean); mv <- mv[order(mv$date), ]
    med <- sapply(seq_len(nrow(mv)), function(i)
      if (i > 60) median(mv$vol_20[max(1, i - 250):(i - 1)]) else NA)
    mv$regime_hi <- as.integer(mv$vol_20 > med)
    merge(d, mv[, c("date", "regime_hi")], by = "date")
  })
  do.call(rbind, out)
}

# Adaptive-fusion inputs (research hypothesis): quantum-walk features gated by regime.
add_fusion_interactions <- function(df) {
  for (m in c("dtqw", "ctqw")) for (c in graph_cols(m)) {
    df[[paste0(c, "_hi")]] <- df[[c]] * df$regime_hi
    df[[paste0(c, "_lo")]] <- df[[c]] * (1 - df$regime_hi)
  }
  df
}
ADAPTIVE_COLS <- c("regime_hi", as.vector(outer(c(graph_cols("dtqw"), graph_cols("ctqw")),
                                                c("_hi", "_lo"), paste0)))

build_dataset <- function(prices, sent = NULL, graph_args = list()) {
  cls <- build_features(prices)
  gf <- do.call(rbind, lapply(split(prices, prices$market), function(p) {
    message("graph features: ", p$market[1])
    g <- do.call(graph_features_market, c(list(prices_mk = p), graph_args))
    g$market <- p$market[1]; g
  }))
  df <- merge(cls, gf, by = c("market", "ticker", "date"))
  df <- add_regime(df)
  df <- add_fusion_interactions(df)
  if (!is.null(sent)) {
    sf <- sentiment_features(df[, c("ticker", "date")], sent)
    df <- merge(df, sf, by = c("ticker", "date"), all.x = TRUE)
  }
  df <- df[order(df$market, df$date, df$ticker), ]
  rownames(df) <- NULL
  df
}

FEATURE_SETS <- list(
  classical          = CLASSICAL_COLS,
  classical_rw       = c(CLASSICAL_COLS, graph_cols("rw")),
  classical_heat     = c(CLASSICAL_COLS, graph_cols("heat")),
  classical_ppr      = c(CLASSICAL_COLS, graph_cols("ppr")),
  classical_dtqw     = c(CLASSICAL_COLS, graph_cols("dtqw")),
  classical_ctqw     = c(CLASSICAL_COLS, graph_cols("ctqw")),
  classical_fusion   = c(CLASSICAL_COLS, graph_cols("dtqw"), graph_cols("ctqw")),
  classical_adaptive = c(CLASSICAL_COLS, ADAPTIVE_COLS),
  classical_sent     = c(CLASSICAL_COLS, SENTIMENT_COLS),
  fusion_sent        = c(CLASSICAL_COLS, graph_cols("dtqw"), graph_cols("ctqw"), SENTIMENT_COLS)
)
