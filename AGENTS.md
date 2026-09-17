# Repository context

This repo is a decision framework for data science teams building analytics and
AI workflows on Snowflake. It is documentation and reference SQL. It contains no
credentials, no data, and no client-specific configuration.

## Working boundaries

- Start with the named workflow, objects, and files. Do not scan the entire account.
- Read the relevant guide only; do not load every document into each conversation.
- Use SQL/scripts for deterministic checks. Ask before broadening scope or launching
  multiple agents. A skill is guidance, not a deterministic enforcement mechanism.
- Stop after two unsuccessful attempts at the same operation and report the evidence.
- Return summaries and small samples, not raw corpora or long query logs.
- Keep client data, account identifiers, credentials, and measured usage out of this public repo.
- Do not create objects in an account until the user approves the destination.
- Do not run billable inference without approval of the preflight scope and estimate.

## What an agent should do here

Help a team adopt the framework. That usually means one of four tasks.

**Assess.** Compare their current stack against the layer contract in
`docs/05_data_and_semantic_layers.md`. Look for the specific gaps: undeclared
grain, metrics defined in more than one place, dashboards reading raw tables,
AI functions re-scoring the same rows, missing gate queries.

**Route.** Given a question or workflow they described, say which tool it belongs
to and why, using `docs/01_decision_framework.md`. Name the cheaper alternative
when there is one.

**Generate.** Produce the missing piece — a semantic view, a gate query, a skill
— adapted from the reference SQL to their schema. Compile-validate anything you
write before handing it over.

**Measure.** Run the queries in `sql/40_cost_observability.sql` against their
account only when asked. Confirm products, CoCo interfaces, and date window first.
Use the relevant usage-view permissions; do not assume ACCOUNTADMIN is required.
Keep CoCo credits, SQL inference, Search, and warehouse compute distinct.

**Reduce CoCo burn.** Follow `docs/08_coco_token_efficiency.md`. Measure credits
per accepted task rather than treating all tokens or requests as equivalent.

## Conventions in the reference SQL

- Names are source-neutral. `SIGNAL_*` and `OUTCOME_*`, never a provider name.
- Every table comment declares its grain. Every grain has a gate query.
- A gate returns rows only on failure. Missing, skipped, errored, or empty-source
  checks do not count as passed.
- Nulls are never coalesced to zero on a score or an index. Carry an explicit
  missing flag instead.
- Features are computed as of a cutoff. Percentiles are ranked within a horizon.
- Predictions are append-only and stamped with the model version live at
  publication.

## What not to do

- Do not add a client name, account identifier, or real data to this repo.
- Do not write a chart library, a CDN link, or an external dependency into the
  HTML in `docs/`. It must render from the filesystem with no network.
- Do not soften the gates. A gate that warns and proceeds is documentation.
- Do not present a recommendation as a Snowflake product claim without checking
  the current docs. Feature availability changes.

## Verification

Run `node --test tests/repository.test.mjs` for local checks. Run the read-only
`tests/enrichment_regression.sql` in Snowflake for scoring-key behavior.
`sql/30` prepares and estimates; `sql/31` is the separately approved inference step.
The measured exercise and migration limits are in `docs/09_measured_exercise.md`.
Never describe static tests or compilation as evidence of model quality or savings.
