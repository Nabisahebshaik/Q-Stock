# Novelty audit (preliminary)

**Status:** a first pass on 2026-10-22, using 6 web searches on one engine plus the publisher/arXiv landing pages listed below.
It is **not exhaustive**. Google Scholar, Scopus and IEEE Xplore were not searched systematically.
No claim below says "first" or "novel" without that qualifier.

Verification levels used:
- **[landing page]**: title, authors and venue read from the publisher or arXiv page.
- **[search summary]**: seen only in search-engine output; must be opened before citing.

## Closest prior work found

| # | Work | Verification | Relation to Q-Stock |
|---|---|---|---|
| P1 | Y.-J. Chang, W.-T. Wang, Y.-Y. Wang, C.-Y. Liu, K.-C. Chen, C.-R. Chang, "Quantum Stochastic Walks for Portfolio Optimization: Theory and Implementation on Financial Networks", arXiv:2507.03963 (v2 Dec 2025); journal ref. *npj Unconventional Computing* 3, 7 (2026) | landing page (arXiv abstract) | Quantum stochastic walk on an asset graph with covariance-kernel edges; uses the stationary distribution for **portfolio weights**, not direction prediction. Claims are self-reported |
| P2 | L. Bai, L. Cui, Y. Wang, Y. Jiao, E. R. Hancock, "A Quantum-inspired Entropic Kernel for Multiple Financial Time Series Analysis", IJCAI 2020, pp. 4453-4460, doi:10.24963/ijcai.2020/614 | landing page (IJCAI proceedings) | Quantum-based entropy of time-varying **NYSE financial networks**, compared with DTW. Used to detect structural change, not to forecast returns. The abstract does not say whether a quantum walk is used |
| P3 | De Backer, Rocha, Ryckebusch, Schoors, "On the potential of quantum walks for modeling financial return distributions", arXiv:2403.19502 | search summary (arXiv page could not be fetched) | DTQW as a **model of return distributions** (skew, heavy tails), not as graph features for a classifier |
| P4 | Same group, arXiv:2505.13019 (2025), long-horizon return distributions with DTQW | search summary | As P3 |
| P5 | GraphQWalk (CTQW-based structural node embeddings, IEEE TNSE); CTQW-GraphSAGE (ICANN 2024); quantum walk neural networks (Dernbach et al.) | search summary | **CTQW/DTQW node features for graph ML exist** in general; not applied to market graphs in what was found |
| P6 | NCCU master's thesis (2025) on an entangled dual-asset quantum walk for price prediction | search summary; accuracy claims unverified | Closest to "QW for prediction", but a different construction (two-asset walk, not a market graph) |

Foundational references (from general knowledge; confirm DOI and venue before citing):
- Aharonov, Davidovich & Zagury, *Phys. Rev. A* 1993 (DTQW)
- Farhi & Gutmann, *Phys. Rev. A* 1998 (CTQW)
- Kempe, *Contemporary Physics* 2003 (review)

## Second search: latest work, 2025–2026 (independent of the student survey)

| # | Work | Verification | Relation to Q-Stock |
|---|---|---|---|
| L1 | C. Zhang, X. Pu, M. Cucuringu, X. Dong, "Forecasting realized volatility with spillover effects: Perspectives from graph neural networks", *Int. J. Forecasting* 41(1):377–397, 2025, doi:10.1016/j.ijforecast.2024.09.002 | landing page (RePEc) | **Graph-augmented HAR is established.** Nonlinear one-hop spillovers help; QLIKE training beats MSE. Our H1 is therefore not novel, and GHAR was added as a baseline (`17_ghar_mcs.R`) |
| L2 | GHAR (linear graph HAR with a Graphical-Lasso precision-matrix graph) as the predecessor of L1 | search summary | Basis of our GHAR baseline; cite after verifying the original reference |
| L3 | J. Shen, "Quantum Kernels and the Cross-Section of Stock Returns: Anatomy of a Vanishing Advantage", arXiv:2607.20168 (Jul 2026) | landing page (arXiv HTML) | Walk-forward with a kernel-swap control; **no quantum advantage**; an apparent edge vanishes under a point-in-time protocol. The design is closest in spirit to our ω-dial |
| L4 | Q. Li, C. Mukhopadhyay, A. Bayat, A. Habibnia, "Quantum Reservoir Computing for Realized Volatility Forecasting", *Phys. Rev. Research* 8, 023028 (2026), arXiv:2505.13933 | landing page (arXiv) | Quantum (Ising reservoir) method for RV with MCS evaluation; claims outperformance. Not a quantum walk |
| L5 | Hybrid quantum circuit Born machine for volatility, arXiv:2603.09789 (2026) | search summary | Quantum generative prior for A-share index volatility; not a quantum walk |
| L6 | Chang et al. QSW portfolio paper (P1), published in *npj Unconventional Computing* (2026) | search summary + arXiv landing page | Confirms publication of P1 |
| L7 | De Backer et al., *Physica A* 657 (2025); follow-up in *Eur. Phys. J. B* 99:51 (2026) | search summary | DTQW models of return distributions |
| L8 | One-switch benchmark for decision-time leakage in financial backtests, arXiv:2605.23959 (2026) | search summary | Leakage-audit tool; candidate for an extra audit of our pipeline |

**Updated verdict for claim 3** (QW node features on market graphs for forecasting):
- In both searches, nothing was found that applies a quantum-walk ω-dial to volatility forecasting.
- The *forecasting value* of such features, however, does not exceed GHAR (L1-style) in our data.
- So the novelty is the **controlled quantum-to-classical audit itself**, not a better forecaster.

## Student literature survey (45 papers, 2024–2026)

Source: `Literature_Survey_UROP_Batch_1_2023.xlsx`, structured by `scripts/09_literature_survey.R` into `docs/literature_survey_structured.csv`.
The derived columns are keyword rules over the survey's own summaries, not a reading of the papers. 44/45 entries have DOI links, which have not been resolved one by one.

* **Methods:** RNN/LSTM/DNN 20, Transformer 4, tree/ensemble 5, SVM/SVR 3, linear/statistical 2, unspecified 11.
* **No paper uses graph, network-diffusion or quantum-walk features** (0/45). That is consistent with claim 3 below.
* **Targets:** 26 predict price levels, 12 direction/trend, 7 unclear.
  Price-level metrics such as R² of 94.7% (#3) or RMSE are dominated by price persistence and do not show predictability.
* **Direction accuracies reported by the survey summaries:** 52.77% (#7, Reliance, LR/RF/XGBoost), about 51.5% (#38, LR), 72% (#8, LSTM).
  Our 50–52% (`docs/results.md`) agrees with #7 and #38. A 72% directional accuracy would be extraordinary for daily data and should be checked for look-ahead or overlapping train/test windows before it is cited as a benchmark.
* **Gaps that recur in the survey's own "Limitation" column:** single stock or a few stocks (≥ 8 papers), no walk-forward evaluation, no transaction costs, no naive baseline, no significance tests. Q-Stock addresses each one:
  - 40 stocks in 2 markets
  - monthly walk-forward with an embargo
  - net-of-cost Sharpe
  - a base-rate baseline
  - DM tests with Holm/BH correction and bootstrap CIs

## Claim-by-claim verdicts

| # | Candidate claim | Verdict (preliminary) |
|---|---|---|
| 1 | Quantum walks applied to financial / market networks | **Not novel.** P1 and P2 already do this |
| 2 | Quantum-walk-derived node features used in ML | **Not novel in general** (P5) |
| 3 | DTQW and CTQW node features on rolling market-correlation graphs, fed to a next-day direction classifier under leakage-controlled walk-forward evaluation, against matched classical-diffusion controls | **Not found in this search.** At best an *incremental, empirical* contribution. Our results show **no predictive benefit**, so the contribution would be a well-controlled negative result |
| 4 | Regime-adaptive DTQW/CTQW fusion | **Not found in this search.** Tested here as a hypothesis and **not supported**: worse log-loss than classical (DM p < 0.001 for logistic regression in both markets) |
| 5 | Quantum-walk features + point-in-time news sentiment | **Not evaluated:** the GDELT download did not complete (see `unresolved_issues.md`) |
| 6 | Hadoop/Hive/Spark pipeline for quantum-walk features | Engineering contribution for the course; not a research novelty claim |

## What to do before any publication

1. Run systematic searches on Google Scholar, Scopus and IEEE Xplore:
   - `"quantum walk" AND (stock OR equity OR "financial network") AND (predict* OR forecast* OR classif*)`
   - `"continuous-time quantum walk" AND (correlation network OR market)`
   - `"discrete-time quantum walk" AND (finance OR stock)`
2. Open and read P1–P6. Record what they evaluate and against which baselines.
3. Frame any paper around the evidence in `docs/results.md`: matched classical controls, a random-graph control, a naive baseline and a negative result.
