# Research questions

All questions are open. None has been answered by this project yet.
Each question names the evidence that would answer it.

**RQ1: Do quantum-walk features carry out-of-sample predictive information?**
On real data, under chronological walk-forward evaluation, do DTQW- or CTQW-derived features on market-state graphs improve next-day direction prediction over a classical feature baseline (returns, volatility, volume)?
*Evidence:* the metric difference with a confidence interval across walk-forward folds, plus a test for equal predictive accuracy (e.g., Diebold–Mariano on the loss series).

**RQ2: Is any gain specific to quantum walks?**
Do quantum-walk features beat classical graph-based features computed on the same graphs: classical random-walk / diffusion distributions, personalized PageRank, heat-kernel diffusion exp(-tL), and spectral/centrality features?
*Evidence:* the same evaluation protocol. Without this control, a gain could come from the graph rather than from quantum interference.

**RQ3: DTQW vs CTQW vs fusion.**
Does combining DTQW and CTQW features help beyond either alone?
*Evidence:* an ablation table.

**RQ4: Adaptive fusion (hypothesis).**
Does weighting DTQW/CTQW features by market regime (e.g., volatility state, estimated using past data only) help?
*Status:* hypothesis only, pending the novelty audit and RQ1–RQ3 results.

**RQ5: Point-in-time sentiment.**
Given reliably timestamped news/sentiment, does adding it (aligned strictly to information available before the prediction time) change the conclusions of RQ1–RQ3?
*Precondition:* a sentiment source with trustworthy publication timestamps. If none is available, this RQ is dropped rather than approximated.

**RQ6: Scalability.**
How do runtime and memory of classical quantum-walk simulation scale with graph size N and walk length?
Up to what N is dense simulation feasible on the available hardware, and what does the Hadoop/Hive layer contribute for data preparation?
*Evidence:* measured runtime and peak memory curves.

## Scope statements

* All quantum walks are **classically simulated** with dense linear algebra. No quantum hardware is used, and no quantum speed-up is claimed.
* Synthetic data is used only to validate software. No predictive or financial claim will rest on synthetic results.
