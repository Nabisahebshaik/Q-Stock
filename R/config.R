# Project-wide configuration. All paths are relative to the project root.

QS <- list(
  start_date = as.Date("2015-01-01"),
  end_date   = as.Date("2026-10-21"),   # last close before the v2 run (fixed for reproducibility)

  # Current large caps. NOTE: choosing today's constituents introduces
  # survivorship bias; this is documented as a limitation in docs/.
  universe = list(
    NSE = c(RELIANCE.NS = "Reliance Industries", TCS.NS = "Tata Consultancy Services",
            HDFCBANK.NS = "HDFC Bank", INFY.NS = "Infosys", ICICIBANK.NS = "ICICI Bank",
            HINDUNILVR.NS = "Hindustan Unilever", ITC.NS = "ITC Limited",
            SBIN.NS = "State Bank of India", BHARTIARTL.NS = "Bharti Airtel",
            KOTAKBANK.NS = "Kotak Mahindra Bank", LT.NS = "Larsen & Toubro",
            AXISBANK.NS = "Axis Bank", ASIANPAINT.NS = "Asian Paints",
            MARUTI.NS = "Maruti Suzuki", SUNPHARMA.NS = "Sun Pharmaceutical",
            TITAN.NS = "Titan Company", BAJFINANCE.NS = "Bajaj Finance",
            WIPRO.NS = "Wipro", HCLTECH.NS = "HCL Technologies",
            ULTRACEMCO.NS = "UltraTech Cement"),
    NASDAQ = c(AAPL = "Apple Inc", MSFT = "Microsoft", NVDA = "Nvidia", AMZN = "Amazon.com",
               GOOGL = "Alphabet", META = "Meta Platforms", TSLA = "Tesla",
               AVGO = "Broadcom", COST = "Costco", PEP = "PepsiCo", ADBE = "Adobe",
               CSCO = "Cisco Systems", INTC = "Intel", AMD = "Advanced Micro Devices",
               QCOM = "Qualcomm", TXN = "Texas Instruments", AMGN = "Amgen",
               INTU = "Intuit", CMCSA = "Comcast", NFLX = "Netflix")
  ),

  # Market-state graph
  corr_window = 60,     # trailing trading days used for correlations
  knn_k = 4,            # neighbours per node before symmetrisation
  walk_steps = 10,      # DTQW / classical RW steps (time-averaged over 1..steps)
  walk_time = 2,        # CTQW / heat-kernel time horizon (averaged over a grid on (0, T])
  ppr_alpha = 0.85,

  # Walk-forward
  train_months = 24,
  min_train_rows = 2000,

  # Backtest
  cost_bps = 10,        # one-way cost per unit of turnover, in basis points

  paths = list(raw = "data/raw", curated = "data/curated", results = "results",
               figures = "results/figures", tables = "results/tables")
)

CLASSICAL_COLS <- c("ret_1", "ret_5", "ret_20", "vol_10", "vol_20", "range", "log_vol_z")
GRAPH_METHODS <- c("rw", "heat", "ppr", "dtqw", "ctqw")
graph_cols <- function(method) paste0(method, c("_self", "_mom", "_ent"))
SENTIMENT_COLS <- c("sent_tone_3", "sent_tone_7", "sent_decay_3", "sent_decay_7", "sent_logvol_7")

ensure_dirs <- function() {
  for (p in QS$paths) dir.create(p, recursive = TRUE, showWarnings = FALSE)
}
