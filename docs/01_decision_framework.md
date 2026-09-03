# The decision framework

Five tools, five cost profiles. The routing question is always the same: what is the cheapest
layer that can answer this correctly and the same way twice?

## The tools

| Tool | Cost driver | Reproducible | Use it for |
|---|---|---|---|
| SQL + visualization | Warehouse seconds. No tokens. | Exactly | A metric someone will ask for again |
| Semantic layer + Cortex Analyst | Warehouse seconds + a small NL-to-SQL token charge per question | Within the governed metric set | Ad-hoc read-only business questions |
| Cortex Search | Indexing credits, then per-query serving | Retrieval is stable, synthesis is not | Grounding a narrative in documents |
| AISQL functions | Tokens times rows. The steepest curve in the stack. | Yes if materialized, no if re-run | Per-row classification, extraction, enrichment |
| Agent reasoning | Tokens times steps times retries | Not by default | Novel problems, debugging, exploration |

## Four routing rules

**Rule 1. If the question recurs, it is not a question. It is a metric.**
The second time a stakeholder asks something, it belongs in the semantic layer or a
materialized table. Answering a recurring question through agent reasoning pays the token
cost every time and gives a slightly different answer every time. Recurrence is the signal to
push the logic down a layer.

**Rule 2. Never spend a token on work a `WHERE` clause can do.**
The most common cost blowup is an AI function evaluating rows that a filter should have
removed first. Filter, dedupe, and sample before the model sees anything. On a large table the
difference between filtering before and after the AI call is often an order of magnitude, and
it changes no result.

**Rule 3. AI output is data. Store it.**
An AI classification is an expensive column, not a transient answer. Write it to a table keyed
so a rerun is a no-op on rows already scored. A pipeline that re-classifies its whole corpus
on every run has no upper bound on cost and no stable history.

**Rule 4. Reasoning is for the first time only.**
Let the agent solve the problem once with full freedom. Then capture the solution as a skill,
a procedure, or a view. The agent's job in production is orchestration and judgment, not
rediscovering a method it already found.

## Routing by question shape

| The stakeholder asks | Route to | Why not the alternative |
|---|---|---|
| "What was X last quarter?" | Curated table, rendered as a chart | An agent re-deriving this is paying tokens to reproduce a known number |
| "Show me X broken out by Y" | Semantic layer via Analyst | Hand-writing the SQL does not scale to the next twelve variants |
| "Why did X move?" | Agent reasoning, grounded on the semantic layer | No fixed query anticipates the cause |
| "What are people saying about X?" | Cortex Search over the text corpus | Aggregating unstructured text in SQL loses the evidence |
| "Classify these 400,000 rows" | AISQL, incremental, materialized | Agent-loop classification costs orders of magnitude more |
| "Run the weekly report" | Agent skill | A free-form prompt will drift week to week |

## What the framework is protecting against

Cost is the visible symptom. The real risk is **plausible wrong output**. An agent with
unbounded reasoning over an ungoverned schema will answer confidently using the wrong
column, a stale table, or a join that silently drops rows. Nothing errors. The number is
merely wrong, and it is wrong differently next week.

Pushing decisions down the stack is a correctness strategy that happens to be cheaper.
`docs/07_repeatability_gates.md` covers the specific defects.
