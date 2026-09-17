---
name: metric-report
description: >
  Produce a standing performance report from the semantic layer, grounded on
  retrieval for narrative context. Use for: weekly report, monthly report,
  title report, performance recap, standing report, slate report. Triggers:
  weekly report, monthly report, performance report, recap, run the report,
  metric report, standing report.
---

# Metric report

A reporting skill. Fixed questions and structure; figures come from approved SQL.
The agent assembles and interprets. LLM prose is not deterministic.

## Setup

Require the repo root (or absolute paths to the adapted SQL), target semantic view,
reporting period, metric set, chart specifications, approved gate runner, and optional
Search service. Stop if any required dependency is missing. These files are not bundled
when this skill folder alone is installed. Do not discover the whole account to infer them.

## Preconditions

Check these first. If any fails, stop and report the failure. Do not proceed
with a partial report.

1. **Gates pass.** Run the approved SQL/script gate runner, not the unadapted
   `sql/50_validation_gates.sql` starter. Require successful execution, nonempty
   expected source populations, no disabled checks, and zero failing rows.
   Missing evidence, skipped checks, or any failure means STOP.
2. **Freshness.** The curated layer's latest load date matches the expected
   as-of date for the reporting period. Assert on the maximum date, not the
   minimum, and not on row count.
3. **Semantic view reachable.** `SHOW SEMANTIC VIEWS` lists the target view and
   the current role holds SELECT and REFERENCES on it.

## Steps

1. **Figures.** Query the semantic view for the standing metric set. Use
   `SELECT * FROM SEMANTIC_VIEW(...)` with named metrics and dimensions. Do not
   hand-write aggregation SQL against the curated tables; if a needed figure is
   not in the metric set, stop and report that gap rather than deriving it.

2. **Deltas.** Compute period-over-period change from the same metric set.
   Deltas come from two calls to the same metric, never from two different
   definitions of it.

3. **Context.** If configured and needed, query Search with the reporting period
   and corpus filters. Start with six relevant chunks within the agreed context
   budget; expand only when missing evidence justifies it. Retrieved text costs
   downstream synthesis tokens, not a per-chunk interactive Search serving fee.
   Search supplies evidence, never population counts.

4. **Charts.** Render from the approved chart set. Select and parameterize an
   existing specification; do not invent a chart shape per run. One chart per
   claim that needs a shape shown; no chart for a single number.

5. **Prose.** Conclusion first, then the evidence. Every figure carries its
   metric name. Every qualitative claim carries its retrieved source.

## Acceptance

A reviewer must be able to check these without rerunning the work.

- Every figure in the report traces to a named semantic-layer metric.
- No figure appears that is absent from the metric set.
- Every horizon-sensitive figure states its horizon. Figures at different
  horizons are never compared.
- Deltas reconcile against the previously published report. A prior published
  figure is never restated with a new value; if the definition changed, say so
  explicitly and show both.
- Every qualitative claim cites a retrieved passage.
- Retrieval-derived counts appear nowhere. Counts come from SQL over
  materialized labels.

## Cost notes

- The whole run should be a handful of semantic-layer calls plus one retrieval
  call. If it is running dozens of exploratory queries, the metric set is
  incomplete; fix the semantic layer rather than letting the agent compensate.
- Set `QUERY_TAG` for SQL attribution, not attribution of the CoCo conversation:
  `ALTER SESSION SET QUERY_TAG = 'workload=metric_report;period=<period>';`
- Never call an AI function on a row set inside this skill. Labels are
  materialized upstream by the separately approved `sql/31_score_approved_batch.sql`. Scoring at
  report time pays per run for work already done.
- Stop after two failed attempts at one operation. Do not spawn additional agents
  to retry the same task. Use an independent reviewer only when the caller requests it.
- Use a fixed SQL/template runner without an agent when no interpretation is needed.

## Output

Report, as-of date, metric/query references, gate evidence, and missing limitations.
No invented savings. Obtain publication approval separately from report generation.
