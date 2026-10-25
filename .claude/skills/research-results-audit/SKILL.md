---
name: research-results-audit
description: Keep research write-ups honest and traceable - audit every number in docs, README and the manuscript against the results CSVs, label pre-registered vs exploratory findings, run a staged novelty audit with verification levels, write session hand-off notes, and frame negative results for a Q1 journal. Use after any results change, before writing or editing docs/results, paper/manuscript_draft.md or README findings, or when assessing novelty claims.
---

# Research results audit and reporting

## Doc-vs-CSV audit (after every results change)

1. List every number in `README.md`, `docs/results/*.md`, `paper/manuscript_draft.md`.
2. Find its source row in `results/tables/*.csv` (the script that wrote it is named in each doc section).
3. Check value, rounding, **pairing** (which ω, market, loss, test the p-value belongs to) and direction of the difference.
4. Fix all copies together; note corrections in `docs/operations/HANDOFF.md`.
   Past catches: ω = 0.25 has Holm p = 4.8e-6, the 4.7e-8 belongs to ω = 0.5; an omitted (significant but negligible) NSE economic result; Spark timing after a re-run.

## Reporting rules

- State scope every time: classical simulation, no quantum speed-up, synthetic data only for validation.
- Separate **pre-registered** (H1–H3 in `docs/research/preregistration_v2.md`) from **exploratory**.
- Report every pre-specified cell, including nulls and the market where the effect fails (NSE).
- Distinguish statistical from practical significance (effect size, economic value, comparison with the strongest classical baseline GHAR).
- A null backed by a power analysis is informative; say what size of effect could have been detected.
- Precondition-gated questions (RQ5 sentiment) are reported as "not evaluated" when the precondition fails, never approximated with partial data.

## Novelty audit (`docs/research/novelty_audit.md`)

- Tag each source: **[landing page]** (title/authors/venue read on the publisher or arXiv page) or **[search summary]** (must be opened before citing).
- Never write "first"/"novel" without "in this search". Give claim-by-claim verdicts: not novel / not found / not evaluated.
- Mark unverified references in the manuscript with **[VERIFY]** and resolve them before submission.
- Current framing: the contribution is the controlled quantum-to-classical audit, not a better forecaster.

## Hand-off notes

Append a dated section to `docs/operations/HANDOFF.md` at the end of significant work: what ran, where its log/output is, what "done" looks like, numbered next steps, key facts, and user preferences learned.
