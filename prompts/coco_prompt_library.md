# Prompt library

Prompts for working through the framework with Cortex Code, grouped by the four
adoption tasks. Replace bracketed placeholders.

Begin with a bounded task. Name objects and files rather than requesting an account-wide
scan. State whether SQL execution, DDL, inference, and publication are permitted.

## Use CoCo efficiently

```text
Use only [FILES / OBJECTS] to complete [TASK]. Acceptance checks: [CHECKS].
Return a concise result and evidence. Do not read raw corpora into chat, scan the
whole account, run model inference, or create objects. Stop after two failed
attempts at the same operation and report the blocker. Ask before widening scope.
```

```text
Read docs/08_coco_token_efficiency.md. Review this workflow: [WORKFLOW]. Separate
CoCo authoring from repeat execution. Identify deterministic work that can run as
SQL/scripts, context that can be removed, and where a stronger model is genuinely
needed. Preserve the acceptance tests. Do not implement changes yet.
```

```text
Prepare a short handoff for a new conversation: objective, decisions, current
files/objects, tests already run, unresolved errors, and the next action. Do not
repeat raw tool output or the whole conversation. Do not save client details to
this public repo.
```

## Assess the current stack

```
Read docs/05_data_and_semantic_layers.md. Then inspect [DATABASE.SCHEMA] and
report where it violates the layer contract. Specifically: tables whose declared
grain is not satisfied, metrics computed in more than one object, views that read
raw tables directly, and joins with undeclared cardinality that could fan out.
Return a table of findings ordered by blast radius. Do not fix anything yet.
```

```
Find every place in [DATABASE.SCHEMA] where a LEFT JOIN result is coalesced to
zero on a numeric column that represents a score, rank, index, or percentile.
For each, tell me what a zero would mean to a downstream consumer versus what a
null would mean.
```

```
List the objects in [DATABASE.SCHEMA] that call an AI function. For each, tell me
whether it scores incrementally or re-scores its whole input on every run, and
estimate the cost difference over a month at the current schedule.
```

## Route a question or workflow

```
Read docs/01_decision_framework.md. Here is a workflow my team runs today:
[DESCRIBE THE WORKFLOW]. Tell me which tool each step belongs to, which steps
should be pushed down a layer, and what the cheaper version looks like.
```

```
Here are the ten questions our stakeholders ask most: [LIST]. For each, say
whether it should be a materialized metric, a semantic-layer question, a
retrieval-grounded narrative, or genuine agent reasoning. Flag any that recur
weekly and are currently answered by an agent.
```

```
We are considering putting an agent in front of [DATASET]. Before I do, tell me
what an agent could get plausibly wrong given the current schema, and what would
have to exist for the same question to return the same number twice.
```

## Generate the missing pieces

```
Read sql/20_semantic_view.sql as a pattern. Build a semantic view over
[DATABASE.SCHEMA] covering these three metrics: [METRICS]. Include synonyms for
how our stakeholders actually phrase them, declare relationship cardinality, and
add AI_SQL_GENERATION instructions for the ambiguities you find. Compile-validate
it before showing me.
```

```
Read sql/50_validation_gates.sql. Write the equivalent gate suite for
[DATABASE.SCHEMA]. Every gate must return rows only on failure. Include a gate
for each declared grain and each dimension join. Compile-validate all of them.
```

```
Read docs/03_agent_skills.md. Here is a workflow we run every [PERIOD]:
[DESCRIBE]. Write it as a skill with preconditions that can fail, steps that name
the layer to query rather than the SQL to write, and acceptance criteria a
reviewer can check without rerunning the work.
```

```
Read sql/30_incremental_ai_enrichment.sql and sql/31_score_approved_batch.sql.
Adapt [OBJECT] to content- and scorer-version-keyed reuse. Cover nullable fields,
changed inputs/config, failed outputs, and single-writer execution. Estimate every
actual AI call over a frozen sample. Show coverage and input tokens; output tokens
and other billable components are separate. Do not run inference or deploy DDL.
```

## Add verified queries

```
Here are the questions our stakeholders asked this quarter and the answers we
agreed were correct: [LIST]. Turn each into a verified query on
[SEMANTIC_VIEW]. Compile-validate the SQL and confirm each one returns the
agreed figure.
```

## Measure cost

```
Use sql/40_cost_observability.sql as reference for [PRODUCTS] over [DATE RANGE].
For CoCo, report [CLI / DESKTOP / SNOWSIGHT / ALL SEPARATELY]. Select only relevant
queries. Report credits, exact source, period, and coverage; distinguish warehouse
compute, AI Functions, CoCo, and Search. Do not add overlapping meters or treat
missing usage as zero. No DDL or model inference.
```

```
Using QUERY_ATTRIBUTION_HISTORY, find the query shapes that ran more than a
hundred times in the last thirty days. For each, tell me whether it is a
materialization candidate and what the saving would be.
```

```
Before we run [AI FUNCTION] over [TABLE], estimate the cost. Use AI_COUNT_TOKENS
with the actual function, model if applicable, and full prompt/config on a
representative sample. Report eligible rows, missing estimates, input-token
projection and uncertainty. Output tokens are additional where billed. Compare
candidate approaches only with the same quality bar. Do not run the batch.
```

## Establish the guardrails

```
Set up cost guardrails for this account per docs/06_cost_model.md: a QUERY_TAG
convention for SQL pipelines, warehouse resource monitors, and separate AI budget
and CoCo per-user limit options. Explain notification versus enforcement and
metering latency. Ask for scope and limits. Show the configuration and wait for
approval before executing anything. Resource monitors do not cap AI-service spend.
```

## Before publishing a number

```
Run the approved deterministic checks at [CHECK PATH] against [DATASET]. Require
nonempty expected sources and successful execution of every enabled check.
Missing, disabled, errored, or failed checks mean STOP. Do not repair or score.
Use the model-validation-gate skill for an independent review only if requested.
Return the verdict and evidence without a second discovery pass.
```
