# Working efficiently with CoCo

Use CoCo to discover and build a method, then reuse the validated implementation.
This guide covers the developer's CoCo session. Production SQL inference and Search
have separate meters and controls in [the cost model](06_cost_model.md).

## Before a session

Give the agent the objective, specific files or fully qualified objects, allowed scope,
and acceptance checks. Say what it must not do: no data writes, no inference batch,
no account-wide scan, or no dependency changes when those restrictions apply.

```text
Review sql/30_incremental_ai_enrichment.sql and sql/31_score_approved_batch.sql
for duplicate-scoring risk. Check null keys, content/config version changes,
and reruns. Use read-only fixtures; no model inference or database objects.
Return actionable findings with file references. Stop after two failed attempts
at the same operation and report the error rather than broadening the task.
```

Use Plan mode when architectural choices need agreement, not for every small edit.
A useful plan prevents discarded implementation work; a long plan for a typo adds
work without improving the result. Define a stopping condition before a broad audit.

## Pick a model for the job

Start routine edits, known SQL patterns, and concise summaries with **Auto Efficient**
or an approved efficient model. Escalate difficult debugging, unfamiliar architecture,
and high-risk reasoning to a more capable model when the quality checks require it.
The in-product model list is authoritative; do not hardcode a model that the team's
role or region cannot use. Auto Efficient optimizes cost but may reduce quality on
hard tasks. See [CoCo Desktop model selection](https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code-desktop).

Compare **credits per accepted task**, not cost per response. A cheap model that
needs repeated repairs can be the expensive choice. Agree on accuracy, tests,
completeness, and review effort before comparing models.

## Keep relevant context and drop the rest

- Name or attach the relevant file, selection, table, or view. Search narrowly before
  asking the agent to read a whole repository, schema, or document collection.
- Query aggregates, column metadata, and small samples. Keep raw corpora, large result
  sets, generated files, build logs, and notebook outputs outside the conversation.
- Use a concise root `AGENTS.md` for essential project rules. Store detailed methods in
  skills and reference files loaded only when needed. Do not duplicate the same rules
  across global instructions, project instructions, and every prompt.
- In Desktop, inspect the context ring and its breakdown. Use `/compact` when continuing
  a long task; start a new conversation for an unrelated task. Preserve decisions,
  current files, tests, and unresolved issues in a short handoff before changing sessions.
- Do not clear context mechanically every few turns. Rebuilding it costs work too, and
  cached input, cache writes, new input, and output have different billing rates.

CoCo already uses automatic tool discovery and large-result offloading. Do not build
another summarization loop merely to duplicate these features. The context indicator
is a context-size estimate, not a billing meter. See [context management](https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code-desktop/context-management)
and [instruction files](https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code-desktop/instruction-files).
`AGENTS.md` is portable across the documented surfaces; `COCO.md` is not a default
Desktop instruction filename unless configured explicitly.

## Bound the agent loop

Set a retry limit and require the agent to explain the blocker before expanding scope.
For routine work, start without subagents. Delegate when isolation or independent review
adds value, not because parallel execution is available. Give each worker a distinct
question, bounded files, and a short return format. Multiple agents can reduce elapsed
time while increasing total token spend.

A skill records a procedure; it does not make execution deterministic or enforce a
budget. Execute stable tests and transformations as SQL or scripts. If an independent
reviewer is required, give it the test evidence and the relevant diff, not a request
to independently rediscover everything. Never save tokens by removing required checks.

## Separate authoring from repeat execution

For recurring data work, let CoCo build and verify a parameterized query, script, or
pipeline. Run the resulting code directly when the procedure is settled. Use an agent
again when interpretation, exceptions, or a code change genuinely requires judgment.
Do not rerun AI enrichment when a notebook cell, dashboard, or report refreshes.

For common reports, query approved metrics and add bounded narrative synthesis only
when it helps the reader. Verified queries guide Analyst generation; they are not a
result cache. Direct SQL against a semantic view does not itself require an LLM call.

## Track usage and put limits in place

Use [SNOWFLAKE_COCO_USAGE_HISTORY](https://docs.snowflake.com/en/sql-reference/account-usage/snowflake_coco_usage_history)
to separate CLI, Desktop, and Snowsight, and inspect user, request, model, and cache
credits. The examples in [sql/40](../sql/40_cost_observability.sql) retain those boundaries.
Do not use an AISQL usage table as a proxy for CoCo spend.

Have an administrator configure appropriate [cost controls](https://docs.snowflake.com/en/user-guide/cortex-code/cost-controls):
budgets for visibility and actions, daily per-surface limits, or per-user quotas for
enforcement. Record the owner, scope, thresholds, exception process, and a tested
notification/blocking path. Allow for metering and enforcement latency.

## Team adoption checklist

- Pick one representative authoring task with explicit acceptance tests.
- Record the baseline model, retries, quality outcome, CoCo credits, and any SQL compute.
- Repeat with narrower context and efficient model routing; keep the acceptance bar fixed.
- Turn the stable procedure into reusable code and a short skill where useful.
- Review the most expensive requests and failed tasks, not just the largest token totals.
- Keep client results and account usage in a private location, not this public starter repo.