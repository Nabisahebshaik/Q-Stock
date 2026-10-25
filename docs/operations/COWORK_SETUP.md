# Setting up Q-Stock in Claude Cowork (and Claude Code)

What a new Claude session needs, and where it comes from.

| Piece | Location | Claude Code | Cowork |
|---|---|---|---|
| Project instructions (ground rules, environment, commands, conventions) | `CLAUDE.md` | loaded automatically | loaded when the project folder is selected |
| Project skills (10) | `.claude/skills/<name>/SKILL.md` | discovered automatically | upload the zips from `build/skills/` |
| Docs entry point | `docs/README.md` → architecture → design | read on demand | read on demand |
| Current state | last section of `docs/operations/HANDOFF.md` | read on demand | read on demand |

## Steps for Cowork

1. Open Claude Desktop → **Cowork** and select the folder `C:\Users\shaik\OneDrive\Desktop\Q-Stock`.
2. Build the skill zips (re-run after any skill change):

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts/28_package_skills.ps1
   ```

3. In claude.ai / Claude Desktop: **Settings → Capabilities → Skills → Upload skill**, once per zip in `build/skills/`. Each zip holds `<name>/SKILL.md`. Re-uploading a skill with the same name replaces it.
4. Start the first task with: "Read CLAUDE.md, docs/README.md and the last section of docs/operations/HANDOFF.md."

`build/` is git-ignored; the zips are generated, the source of truth is `.claude/skills/`.

## Skills

| Skill | Covers |
|---|---|
| `quantum-walk-simulation` | DTQW, CTQW, QSW (ω dial), walk features, physics invariants |
| `leakage-safe-forecast-evaluation` | point-in-time features, embargoed walk-forward, HAR/GHAR, DM + Holm/BH, bootstrap, MCS, power, SHAP |
| `hadoop-hive-spark-pipeline` | Cloudera VM, WebHDFS, Java MapReduce, Hive via beeline, Spark via sparklyr |
| `duckdb-parquet-storage` | DuckDB candle store, Parquet history and prices cache, SQLite rollback, migration, benchmark |
| `live-market-data-pipeline` | exchange sessions, 1-min polling, candle store, tick aggregator, live graph and forecast |
| `chart-workspace-bars-indicators` | `/api/bars`, interval roll-ups, 5 s snapshot bars, R indicators, chart UI and drawings |
| `r-plumber-react-dashboard` | plumber API, React + three.js UI, snapshot fallback, Shiny dashboard |
| `free-tier-r-deployment` | Render (Docker R API) and Vercel (UI) free tiers |
| `gpu-and-long-run-safety` | torch/CUDA runs, overnight chains, thermal guard (87 °C) |
| `research-results-audit` | numbers traced to CSVs, pre-registered vs exploratory, novelty audit, hand-off notes |

## Notes for Cowork sessions

- R is not on PATH; use the full `Rscript.exe` path from `CLAUDE.md`.
- The Cloudera VM, GPU jobs and the live API run on the laptop. A session without access to them can still read, plan and edit, but must say when a result was not re-run.
- Never commit unless asked; large outputs stay in git-ignored paths (the project is in OneDrive).
