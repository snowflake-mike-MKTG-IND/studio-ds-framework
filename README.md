# Studio DS Framework

A practical guide for data science teams reducing AI token spend in Snowflake and CoCo
without giving up quality, coverage, or reproducibility.

This repo answers four questions that come up once a team moves past notebooks and starts
putting agents in front of stakeholders:

1. When should an answer be a **chart** instead of a conversation?
2. When should a workflow be an **agent skill** instead of a prompt?
3. When should a report be built on **Cortex Search** instead of SQL?
4. What has to exist in the **data and semantic layers** before agent output is repeatable?

Start with [Working efficiently with CoCo](docs/08_coco_token_efficiency.md) for developer
habits, [Cost model](docs/06_cost_model.md) for production workloads and controls, and
[Measure incremental scoring](docs/09_measured_exercise.md) for a hands-on exercise.
The existing tool map explains where to move recurring work out of the agent loop.

## The core principle

Push each decision as far down the stack as it will go.

```
Agent reasoning        exploration and judgment        <- bound steps and retries
  Agent skill          reusable instructions            <- still uses an LLM
    Semantic layer     named metrics and relationships  <- SQL directly or via Analyst
      Curated tables   reusable data and AI outputs     <- no repeated inference
        Raw            landed source                    <- curate before consumption
```

Known SQL executed directly avoids conversational inference. Asking an agent to re-derive
the same calculation adds token cost and opportunities for inconsistency. This is a routing
heuristic, not a universal product-cost ranking. Measure credits per accepted task or per
validated record alongside quality, rather than optimizing token count alone.

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
| [`docs/08_coco_token_efficiency.md`](docs/08_coco_token_efficiency.md) | Scope, model selection, context, retries, delegation, reuse, and CoCo controls. |
| [`docs/09_measured_exercise.md`](docs/09_measured_exercise.md) | First run, unchanged rerun, changed input, changed scorer; measure quality and real usage. |

## Reference SQL

Source-neutral starter patterns, not a production installer. Approve a development
database and adapt `STUDIO_DS` before running DDL. Do not run every SQL file as a batch:
`31` is deliberately separated because it performs billable inference.

| File | Purpose |
|---|---|
| `sql/00_layer_contract.sql` | Schema conventions for raw / curated / semantic layers |
| `sql/10_curated_feature_view.sql` | An as-of-correct feature view, the pattern that prevents leakage |
| `sql/20_semantic_view.sql` | Semantic view with metrics, dimensions, synonyms, verified queries |
| `sql/30_incremental_ai_enrichment.sql` | Setup, versioned/null-safe keys, frozen 100-row batch, two-function token preflight; no inference |
| `sql/31_score_approved_batch.sql` | Explicitly approved inference, stored responses, serial idempotent persistence, failed-output review |
| `sql/32_enrichment_quality.sql` | Result/gold-key checks, coverage, per-class precision/recall, macro F1 |
| `sql/40_cost_observability.sql` | Current AI Functions, CoCo by interface/model/cache, Search, Agents, Analyst, and warehouse usage |
| `sql/41_enrichment_run_cost.sql` | Scoring credits per 1,000 validated items, with incomplete telemetry visible |
| `sql/50_validation_gates.sql` | The gate queries that must return zero rows before publishing |

The `00`/`10`/`20`/`50` analytical examples require adaptation to the source and training
contract. They are not an end-to-end ingestion pipeline. Empty sources and skipped checks
are not proof of readiness. See the limitations in [repeatability gates](docs/07_repeatability_gates.md).

## Agent skills

`skills/` holds two examples to adapt to your approved object names and metric set.

- `metric-report/` — a **reporting** skill: fixed metric set and output structure,
  retrieval for context. Bounded scope, not a deterministic LLM-output guarantee.
- `model-validation-gate/` — a **gating** skill: runs checks, refuses to proceed on failure.
  The pattern that keeps an agent from confidently publishing a broken number.

For local installation, put the adapted folder under `~/.snowflake/cortex/skills/`.
Keep this repo available, or replace every repo-relative SQL path with the approved
absolute path. The skills must stop if their dependency files or configuration are missing.
Snowsight uses workspace personal skills; see [the skills documentation](https://docs.snowflake.com/en/user-guide/cortex-code/cortex-code-snowsight).

## Using this with Cortex Code

`AGENTS.md` provides concise project instructions. Open the repo in CoCo and start with
one named workflow from [the prompt library](prompts/coco_prompt_library.md). Specify
scope and acceptance checks; do not begin with an account-wide discovery request.

## Verification

From the repository root, run `node --test tests/repository.test.mjs` (Node.js 18+;
no package installation). These are static repository checks, not Snowflake execution.
Run `tests/enrichment_regression.sql` and `tests/response_regression.sql` in Snowflake
for read-only key/rerun and response-parsing fixtures; neither creates objects or calls
models. The measured exercise requires separate
approval for inference. No model accuracy, production readiness, or savings are implied
by compilation or fixture checks. Product documentation was reviewed on 2026-09-17.

## License

MIT. No credentials, no data, no client-specific configuration in this repo.
