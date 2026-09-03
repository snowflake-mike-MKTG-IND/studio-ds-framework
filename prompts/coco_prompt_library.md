# Prompt library

Prompts for working through the framework with Cortex Code, grouped by the four
adoption tasks. Replace bracketed placeholders.

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
Read sql/30_incremental_ai_enrichment.sql. Convert [OBJECT] from full re-scoring
to incremental scoring keyed on the business tuple. Show me the token estimate
for the first run and for a typical subsequent run.
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
Run the queries in sql/40_cost_observability.sql against this account. Tell me
the split between warehouse and token credits over the last thirty days, the
three largest token line items, and whether Cortex Search spend is dominated by
indexing or serving.
```

```
Using QUERY_ATTRIBUTION_HISTORY, find the query shapes that ran more than a
hundred times in the last thirty days. For each, tell me whether it is a
materialization candidate and what the saving would be.
```

```
Before we run [AI FUNCTION] over [TABLE], estimate the cost. Use AI_COUNT_TOKENS
on a sample, multiply to the full row count, and tell me what a smaller model
would cost for the same task. Do not run the batch.
```

## Establish the guardrails

```
Set up cost guardrails for this account per docs/06_cost_model.md: a QUERY_TAG
convention for our pipelines, a resource monitor on any warehouse an agent can
reach, and a budget covering the Cortex services. Show me the SQL and wait for
approval before executing anything.
```

## Before publishing a number

```
Run the model-validation-gate skill as a subagent against [DATASET]. Report the
verdict verbatim. If it says STOP, do not proceed to scoring and do not repair
the data; tell me what failed and what the remediation would be.
```
