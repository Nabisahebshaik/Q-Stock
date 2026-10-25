# Q-Stock documentation

Start with **architecture**, then **design**. Use **operations** to run things, **research** for what was planned, and **results** for what was found.

```
docs/
├── README.md                     this index
├── architecture/
│   └── ARCHITECTURE.md           system context, layers, data flows, Big Data layer, serving, deployment, stack
├── design/
│   ├── CHART_WORKSPACE.md        TradingView-style chart: /api/bars contract, intervals incl. snapshot-built 5s, indicators, drawing tools
│   ├── DUCKDB_MIGRATION.md       live-candle and price storage on DuckDB + Parquet: design, migration, measured results
│   └── DESIGN.md                 modules, algorithms (graph, DTQW/CTQW/QSW), walk-forward, data model, API contract, UI, tests, decisions
├── research/
│   ├── research_questions.md     RQ1–RQ6 and scope statements
│   ├── preregistration_v2.md     v2 hypotheses H1–H4, ω grid, decision rules (written before any v2 run)
│   ├── novelty_audit.md          prior work, claim-by-claim novelty verdicts
│   └── literature_survey_structured.csv   45-paper student survey, structured by scripts/09
├── results/
│   ├── results.md                consolidated final results (v1 + v2 + tuning + GPU + RQ5 status)
│   └── results_v2.md             full v2 tables: dial, H1–H3, GHAR/MCS, power, SHAP, economic value
├── operations/
│   ├── runbook.md                end-to-end reproduction, VM start-up, pipeline steps
│   ├── environment_report.md     host, VM and toolchain as observed
│   ├── unresolved_issues.md      issues log (resolved and open)
│   └── HANDOFF.md                chronological session hand-off notes and deployment state
└── course/
    └── course_outcome_mapping.md CSE 465 topic-to-evidence mapping
```

| I want to… | Read |
|---|---|
| Understand how the system fits together | [architecture/ARCHITECTURE.md](architecture/ARCHITECTURE.md) |
| Change code in `R/`, `api/` or `web/` | [design/DESIGN.md](design/DESIGN.md) |
| Re-run the pipeline or start the VM | [operations/runbook.md](operations/runbook.md) |
| Know the headline numbers | [results/results.md](results/results.md) |
| Check what was pre-registered | [research/preregistration_v2.md](research/preregistration_v2.md) |
| Resume work in a new session | [operations/HANDOFF.md](operations/HANDOFF.md), then [../CLAUDE.md](../CLAUDE.md) |

The manuscript draft is in [`../paper/manuscript_draft.md`](../paper/manuscript_draft.md).
