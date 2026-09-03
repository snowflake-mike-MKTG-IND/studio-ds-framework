# Cost model

Two meters run in a Snowflake DS workload. Warehouse credits bill for compute time. Token
credits bill for model inference. They fail in different ways and get controlled by different
levers.

## Where credits actually go

**Warehouse cost is dominated by repetition, not by size.** A heavy query run once a month is
rarely the problem. The same moderate aggregation running behind a dashboard, per viewer, per
page load, is. The fix is materialization, not a bigger warehouse.

**Token cost is dominated by row count and by retries.** The per-call charge is small enough
to be invisible in development and decisive at production volume. An AI function on a million
rows is the largest single line item most teams will encounter, and the second largest is an
agent loop that retries because its inputs were in a bad state.

## The steep curve

AISQL cost scales as rows times tokens per row. That means the three levers, in order of
effect:

**Reduce rows.** Filter before the model, not after. Deduplicate before the model. If the task
is measurement rather than enrichment, score a sample and report an interval instead of
scoring the population.

**Reduce tokens per row.** Truncate inputs to what the task needs. Ask for a label, not a
paragraph explaining the label. Structured output is cheaper than prose and easier to
aggregate.

**Never score the same row twice.** Incremental scoring keyed on the business tuple, so a
rerun touches only new rows. See `sql/30_incremental_ai_enrichment.sql`. This is the
difference between a pipeline whose cost is proportional to new data and one whose cost is
proportional to total data times run frequency.

## Right-size the model

Model choice is usually a larger lever than prompt engineering. A short classification into a
handful of labels does not need a frontier model. Fixed-purpose functions like `AI_SENTIMENT`
and `AI_CLASSIFY` are cheaper than a general completion doing the same job. For a
high-volume task with stable labels, a fine-tuned small model can replace a large general one
at a fraction of the cost per row.

The discipline that makes this safe is a labeled evaluation set. Build a few hundred
human-labeled examples, measure macro F1, and treat any model swap as a change that must clear
the same bar. Without that set, downgrading is a guess, and the failure is quiet.

## Estimate before you run

`AI_COUNT_TOKENS` prices a batch before you pay for it. Run it against a sample, multiply, and
compare to what the answer is worth. A ten-minute estimate has prevented more overspend than
any dashboard.

## Measure it on your own account

`sql/40_cost_observability.sql` contains the queries. They read from:

| View | Answers |
|---|---|
| `CORTEX_FUNCTIONS_USAGE_HISTORY` | Token credits by function and model over time |
| `CORTEX_FUNCTIONS_QUERY_USAGE_HISTORY` | Token credits per query, joinable to `QUERY_HISTORY` |
| `CORTEX_AISQL_USAGE_HISTORY` | AISQL usage with `QUERY_TAG`, so spend attributes to a workload |
| `CORTEX_AGENT_USAGE_HISTORY` | Token credits per agent, per request |
| `CORTEX_ANALYST_USAGE_HISTORY` | Credits and request counts for semantic-layer questions |
| `CORTEX_SEARCH_DAILY_USAGE_HISTORY` | Search credits split by consumption type, indexing against serving |
| `WAREHOUSE_METERING_HISTORY` | Warehouse credits by hour |
| `QUERY_ATTRIBUTION_HISTORY` | Warehouse credits attributed to a single query or query hash |

Two practical notes. `CORTEX_FUNCTIONS_QUERY_USAGE_HISTORY` carries no timestamp, so join it
to `QUERY_HISTORY` on `QUERY_ID` to filter by date. And `QUERY_TAG` is the only thing that
makes spend attributable to a workload rather than a user, so set it at the session level in
every pipeline.

## Guardrails worth putting in place on day one

- A `QUERY_TAG` convention, set in every scheduled job and pipeline.
- A resource monitor on any warehouse an agent can reach.
- A budget covering the Cortex services, checked weekly.
- Warehouse auto-suspend at sixty seconds or less for interactive warehouses.
- A separate, small warehouse for agent traffic, so exploratory work cannot borrow a
  production warehouse's size.

## The framing to give a finance stakeholder

Cost per answer, tracked by workload. A recurring question whose cost per answer is not falling
over time is a question that should have been pushed down a layer. That single metric turns the
whole framework into something reportable.
