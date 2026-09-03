# Repository context

This repo is a decision framework for data science teams building analytics and
AI workflows on Snowflake. It is documentation and reference SQL. It contains no
credentials, no data, and no client-specific configuration.

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
account and tell them where credits are going. This requires IMPORTED
PRIVILEGES on the SNOWFLAKE database.

## Conventions in the reference SQL

- Names are source-neutral. `SIGNAL_*` and `OUTCOME_*`, never a provider name.
- Every table comment declares its grain. Every grain has a gate query.
- A gate returns rows only on failure. Zero rows means pass.
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

## Sequencing an adoption

Do not build the whole layer cake before shipping anything. Take the three
most-requested metrics, drive them from raw through the semantic layer, point one
agent at them, and ask the same question twenty times. If the twenty answers do
not agree, something below is still ambiguous. Widen only after that is boring.
