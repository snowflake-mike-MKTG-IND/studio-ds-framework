# Studio DS Framework

A decision framework for data science teams building analytics and AI workflows on Snowflake.

This repo answers four questions that come up once a team moves past notebooks and starts
putting agents in front of stakeholders:

1. When should an answer be a **chart** instead of a conversation?
2. When should a workflow be an **agent skill** instead of a prompt?
3. When should a report be built on **Cortex Search** instead of SQL?
4. What has to exist in the **data and semantic layers** before agent output is repeatable?

Every answer here is also a cost answer. Warehouse credits and token credits are spent by
*where in the stack a decision gets made*, so the routing rules and the cost rules are the
same rules.

## The core principle

Push each decision as far down the stack as it will go.

```
Agent reasoning        most tokens, least reproducible   <- novel problems only
  Agent skill          bounded tokens, deterministic     <- recurring workflows
    Semantic layer     small tokens, governed SQL        <- ad-hoc business questions
      Curated tables   warehouse only, zero tokens      <- known metrics
        Raw            storage                          <- never queried directly
```

A question answered by a materialized metric costs warehouse seconds. The same question
answered by an agent that re-derives the metric costs warehouse seconds plus tokens plus a
reproducibility risk. The framework is mostly about noticing which one you are doing.

## Start here

| File | What it covers |
|---|---|
| [`docs/tool-decision-matrix.html`](docs/tool-decision-matrix.html) | Open in a browser. Visual tool map, decision tree, cost profile per tool. |
| [`docs/01_decision_framework.md`](docs/01_decision_framework.md) | The routing rules in prose, with the failure mode each one prevents. |
| [`docs/02_visualizations.md`](docs/02_visualizations.md) | When a chart is the right deliverable, and when it is a way of avoiding a decision. |
| [`docs/03_agent_skills.md`](docs/03_agent_skills.md) | Promoting a prompt to a skill. Structure, acceptance checks, when not to. |
| [`docs/04_cortex_search_reports.md`](docs/04_cortex_search_reports.md) | Retrieval-grounded reporting, and the numeric work Search should never do. |
| [`docs/05_data_and_semantic_layers.md`](docs/05_data_and_semantic_layers.md) | The layer contract. What makes agent output repeatable. |
| [`docs/06_cost_model.md`](docs/06_cost_model.md) | Where credits actually go, with the queries to prove it on your own account. |
| [`docs/07_repeatability_gates.md`](docs/07_repeatability_gates.md) | Validation gates. Six defects that pass every unit test and still ship wrong numbers. |

## Reference SQL

Runnable, source-neutral, no proprietary data.

| File | Purpose |
|---|---|
| `sql/00_layer_contract.sql` | Schema conventions for raw / curated / semantic layers |
| `sql/10_curated_feature_view.sql` | An as-of-correct feature view, the pattern that prevents leakage |
| `sql/20_semantic_view.sql` | Semantic view with metrics, dimensions, synonyms, verified queries |
| `sql/30_incremental_ai_enrichment.sql` | Score each row with AI once, never twice |
| `sql/40_cost_observability.sql` | Token and warehouse spend by workload, from `ACCOUNT_USAGE` |
| `sql/50_validation_gates.sql` | The gate queries that must return zero rows before publishing |

## Agent skills

`skills/` holds two installable examples that show the two shapes a skill takes.

- `metric-report/` — a **reporting** skill: fixed semantic-layer questions, fixed narrative
  structure, retrieval for context. Deterministic output, bounded token cost.
- `model-validation-gate/` — a **gating** skill: runs checks, refuses to proceed on failure.
  The pattern that keeps an agent from confidently publishing a broken number.

Drop either folder into `~/.snowflake/cortex/skills/` to install locally.

## Using this with Cortex Code

`COCO.md` gives an agent the context to walk a team through adoption. Open the repo in
Cortex Code and ask it to assess your current stack against the layer contract in
`docs/05`, then generate the missing pieces.

## License

MIT. No credentials, no data, no client-specific configuration in this repo.
