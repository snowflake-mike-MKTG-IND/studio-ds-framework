# The decision framework

Five tools, five cost profiles. The routing question is always the same: what is the cheapest
layer that can answer this correctly and the same way twice?

## The tools

| Tool | Cost driver | Reproducible | Use it for |
|---|---|---|---|
| Existing SQL + visualization | Compute and hosting; no inference required for rendering | Same SQL and data snapshot | A metric someone will ask for again |
| Semantic layer + Cortex Analyst | SQL compute + Analyst usage; direct semantic SQL avoids Analyst inference | Governed definitions; validate generated SQL | Ad-hoc read-only business questions |
| Cortex Search | Embedding/refresh, indexed-size serving, storage; synthesis separate | Validate retrieval quality and source freshness | Grounding a narrative in documents |
| AISQL functions | Tokens times rows. The steepest curve in the stack. | Yes if materialized, no if re-run | Per-row classification, extraction, enrichment |
| Agent reasoning | Tokens times steps times retries | Not by default | Novel problems, debugging, exploration |

## Four routing rules

**Rule 1. Recurrence is a signal to reuse work.**
A repeated calculation is a candidate for a metric or parameterized query. Recurring
judgment may still need an agent, but its data preparation should not be reinvented.
Measure query frequency and refresh cost before adding a materialized source.

**Rule 2. Never spend a token on work a `WHERE` clause can do.**
The most common cost blowup is an AI function evaluating rows that a filter should have
removed first. Filter, dedupe, and sample before the model sees anything. On a large table the
difference between filtering before and after the AI call is often an order of magnitude, and
it changes no result.

**Rule 3. AI output is data. Store it.**
An AI classification is an expensive column, not a transient answer. Reuse it for the same
input and scorer version; retain old results when text, model policy, or instructions change.
Serialize writers and record failed attempts so reruns do not become an uncontrolled retry loop.

**Rule 4. Separate discovery from execution.**
Let the agent develop a method within an agreed scope. Capture settled logic as code, a
procedure, or a view, with a short skill when orchestration needs guidance. Keep an agent
for genuine judgment and exceptions, not repeated discovery of the same implementation.

## Routing by question shape

| The stakeholder asks | Route to | Why not the alternative |
|---|---|---|
| "What was X last quarter?" | Curated table, rendered as a chart | An agent re-deriving this is paying tokens to reproduce a known number |
| "Show me X broken out by Y" | Semantic layer via Analyst | Hand-writing the SQL does not scale to the next twelve variants |
| "Why did X move?" | Agent reasoning, grounded on the semantic layer | No fixed query anticipates the cause |
| "What are people saying about X?" | Cortex Search over the text corpus | Aggregating unstructured text in SQL loses the evidence |
| "Classify these 400,000 rows" | AISQL, incremental, materialized | A per-record agent loop adds orchestration and context overhead |
| "Run the weekly report" | Fixed SQL/template, with a skill if synthesis is needed | A free-form prompt adds avoidable interpretation |

## What the framework is protecting against

Cost is the visible symptom. The real risk is **plausible wrong output**. An agent with
unbounded reasoning over an ungoverned schema will answer confidently using the wrong
column, a stale table, or a join that silently drops rows. Nothing errors. The number is
merely wrong, and it is wrong differently next week.

Pushing decisions down the stack is a correctness strategy that happens to be cheaper.
`docs/07_repeatability_gates.md` covers the specific defects.

The product-cost boundaries and current sources are in [the cost model](06_cost_model.md).
These routing rules are recommendations, not guarantees of deterministic agent behavior.
