# Cost model

Measure AI inference and warehouse compute separately. CoCo development, SQL AI
enrichment, and serving stakeholder answers are different workloads. Reducing one
does not prove the others fell. Reviewed against the linked documentation on 2026-09-17.

## Reduce unnecessary inference

**Reduce rows first.** Use deterministic filters and deduplication before inference.
Persist the approved candidate batch before calling a model, rather than relying on
optimizer evaluation order around an AI predicate. For population measurement, use a
representative sample and report uncertainty. For per-record activation, a sample may
not meet the task's coverage requirement.

**Reuse results for identical inputs and scorer versions.** A result key needs the
content and all context that affects the answer, plus the prompt/configuration and
model policy. Changed text or instructions require a new result. Null-safe,
unambiguous serialization matters. An anti-join or MERGE on standard tables alone
does not guarantee exactly-once inference with concurrent writers or interrupted runs.

**Reduce unnecessary input and output.** Extract the relevant passage, avoid repeating
the same instructions, and ask for the smallest useful result. Removing examples or
truncating text can reduce accuracy; evaluate the change. A short label usually uses
fewer output tokens than a rationale, but JSON is not automatically cheaper than prose.
For generative calls, choose an appropriate output-token limit and account for output
and reasoning tokens where the model bills them.

**Choose the cheapest approach that passes the quality bar.** Start with a dedicated
function when it fits. Compare its measured cost and accuracy with alternatives, not
just model size. A small conventional classifier may suit stable labels; include its
training, serving, maintenance, and coverage costs. Use a capable model for exceptions
only when a validated routing rule identifies them. Self-reported confidence is not
a calibrated error probability.

## Estimate and approve the actual batch

`AI_COUNT_TOKENS` estimates **input tokens**, not credits or the final bill. It takes
the function name first, then the model when applicable, text, and relevant options.
Labels, task descriptions, and examples add to input size. Estimate every call in a
multi-function pipeline. Null estimates are unknown, not zero.

Use a representative sample for large populations, and measure the bounded pilot
directly. Account for output tokens where billed. Claude structured outputs can add
billable input content not captured by the estimate. The estimator itself consumes
warehouse compute, not inference-token credits. See [AI_COUNT_TOKENS](https://docs.snowflake.com/en/sql-reference/functions/ai_count_tokens).

The example separates [setup/preflight](../sql/30_incremental_ai_enrichment.sql) from
[approved scoring](../sql/31_score_approved_batch.sql). It defaults to 100 rows, an
illustrative 100,000-input-token ceiling, and approval disabled. Those are starter
limits, not a universal safety threshold or a hard credit cap.

## Measure each product with its own meter

[sql/40_cost_observability.sql](../sql/40_cost_observability.sql) contains independent,
read-only examples for 30 complete calendar days. Confirm the reporting timezone and
use shorter windows for investigation. Required permissions vary by view; use the
relevant Snowflake database roles rather than requiring ACCOUNTADMIN for analysts.

| Workload | Source and boundary |
|---|---|
| SQL AI Functions | [CORTEX_AI_FUNCTIONS_USAGE_HISTORY](https://docs.snowflake.com/en/sql-reference/account-usage/cortex_ai_functions_usage_history): `CREDITS`, `QUERY_ID`, `QUERY_TAG`, `METRICS`; includes in-flight work, up to five-minute latency |
| CoCo CLI, Desktop, Snowsight | [SNOWFLAKE_COCO_USAGE_HISTORY](https://docs.snowflake.com/en/sql-reference/account-usage/snowflake_coco_usage_history): `INTERFACE`, user/request IDs, `TOKEN_CREDITS`, granular model and cache credits; up to one-hour latency |
| Direct Cortex Agents | [CORTEX_AGENT_USAGE_HISTORY](https://docs.snowflake.com/en/sql-reference/account-usage/cortex_agent_usage_history): request and agent costs; not a proxy for every agentic surface |
| Direct Analyst | [CORTEX_ANALYST_USAGE_HISTORY](https://docs.snowflake.com/en/sql-reference/account-usage/cortex_analyst_usage_history): credits and request counts; no per-model token breakdown |
| Cortex Search | [CORTEX_SEARCH_DAILY_USAGE_HISTORY](https://docs.snowflake.com/en/sql-reference/account-usage/cortex_search_daily_usage_history): serving/embedding by service; refresh warehouse and storage are separate |
| Warehouse total | [WAREHOUSE_METERING_HISTORY](https://docs.snowflake.com/en/sql-reference/account-usage/warehouse_metering_history): includes idle compute; cloud-services adjustment is separate |
| Warehouse query attribution | [QUERY_ATTRIBUTION_HISTORY](https://docs.snowflake.com/en/sql-reference/account-usage/query_attribution_history): query compute, excluding idle time; may lag up to eight hours |

Do not use `CORTEX_FUNCTIONS_USAGE_HISTORY` for current monitoring: it is
[no longer updated](https://docs.snowflake.com/en/sql-reference/account-usage/cortex_functions_usage_history).
The older [CORTEX_AISQL_USAGE_HISTORY](https://docs.snowflake.com/en/sql-reference/account-usage/cortex_aisql_usage_history)
does expose `QUERY_TAG`, but the newer AI Functions view provides broader coverage.
Do not add overlapping legacy and replacement views together.

Tag SQL jobs with a workload and run ID. CoCo's own usage is attributed using its
request, user, interface, and user tags; a SQL session `QUERY_TAG` does not label the
surrounding CoCo conversation. Do not sum product drill-downs into an account invoice
without reconciling their coverage and embedded-tool billing.

## Use a denominator that represents useful work

An AISQL usage row represents a query/function/model usage window, not one classified
record. A CoCo request is not necessarily one completed task. Changing batch size or
adding a second function must not manufacture an efficiency gain.

Track AI credits per 1,000 successfully validated records, plus attempted, failed,
excluded, and pending counts. Track CoCo credits per accepted task with its quality
checks and retry count. Report gold-set accuracy separately: a valid label is not proof
of a correct label. [sql/41](../sql/41_enrichment_run_cost.sql) measures persisted scoring
queries; it excludes preparation, merge, idle, and orphaned/failed-query costs. Reconcile
all run-tagged queries for a full pipeline total. Missing telemetry remains unknown.

## Put controls at the correct boundary

- Resource monitors control warehouse consumption, **not AI-service credits**. See
  [resource monitors](https://docs.snowflake.com/en/user-guide/resource-monitors).
- Budgets monitor spend and can trigger notifications/actions, but are periodic rather
  than an instantaneous per-call cap. Use [CoCo daily limits and per-user quotas](https://docs.snowflake.com/en/user-guide/cortex-code/cost-controls)
  where enforcement is needed; include evaluation latency and headroom.
- Require batch approval, bounded candidates, bounded retries, and a failure path that
  stops rather than retries indefinitely. Estimate failure is not permission to guess zero.
- Use a right-sized warehouse and workload-appropriate auto-suspend. Sixty seconds is
  a reasonable starting point for intermittent standard warehouses, not every warehouse
  type or latency-sensitive application. Measure cold starts and repeated resumes.

## Compare like with like

Keep the task, evaluation set, coverage, and success criteria fixed. Include retries and
review effort. A higher-quality answer may legitimately cost more. There is no universal
ordering of product costs and no requirement that every mature workload get cheaper
every week. Optimize the cost-quality tradeoff you actually measure.