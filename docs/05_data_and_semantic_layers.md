# Data and semantic layers

Agent output is repeatable when the agent has no discretion over what a metric means. Every
piece of interpretive latitude left in the schema becomes variance in the answer. The layers
exist to remove that latitude one level at a time.

## The four layers

```
RAW        Landed source data. Append-only. Nobody queries it directly.
CURATED    Conformed, deduplicated, tested. One row per business grain.
SEMANTIC   Named metrics and dimensions with synonyms and verified queries.
INTERFACE  Skills, agents, dashboards. Consume the semantic layer only.
```

The rule that gives this its value: **each layer may only read the layer directly below it.**
A dashboard that reaches into RAW because a curated column was missing is how a second,
divergent definition of a metric gets born.

## The curated layer contract

Four properties. All four are checkable, and `sql/50_validation_gates.sql` checks them.

**Declared grain.** Every table states its primary key in a comment and satisfies it. Grain
ambiguity is the single largest source of silently wrong aggregates, because a duplicate does
not error, it just moves the average.

**Dedupe on content, not identity.** The same record arriving under two different surrogate
keys is common when a source is polled more than once or keyed more than one way. Dedupe on
the business tuple, not the ID.

**Nulls distinguished from zeros.** A missing join must not become a zero. A zero on a score
means "lowest", a null means "unknown", and conflating them is invisible in every summary
statistic. Carry an explicit `__MISSING` flag and impute deliberately.

**Point-in-time correctness.** If any consumer is a model or a forecast, features must be
computed as of a cutoff, using only rows that existed then. Percentiles, ranks, and
normalizations computed across the full history leak the future into the past, and the symptom
is accuracy that looks excellent in backtest and does not survive contact with production.
See `sql/10_curated_feature_view.sql`.

## The semantic layer

A semantic view is where a metric acquires a single definition. It carries:

- **Metrics** with the aggregation written once. `total_revenue` is `SUM(revenue)` and nothing
  else, forever.
- **Dimensions** with declared hierarchies, so a rollup cannot be assembled wrongly.
- **Relationships** with declared cardinality, so a join cannot fan out.
- **Synonyms**, so "gross", "box office", and "revenue" all resolve to the same metric instead
  of three ad-hoc derivations.
- **Verified queries**, which are the highest-leverage element. A reviewed question and its
  correct SQL, stored. The next time that question is asked in any phrasing, the answer is
  retrieved rather than regenerated.

Verified queries are how a semantic layer gets more reliable and cheaper at the same time. Each
one removes a class of question from the generation path.

See `sql/20_semantic_view.sql`.

## What this buys the agent

| Without the layers | With the layers |
|---|---|
| Agent inspects the schema on every run | Metric names are the interface |
| Metric definitions vary by run | Defined once, in one place |
| Silent fanout on an undeclared join | Cardinality declared, join constrained |
| Large context spent on schema discovery | Small context, mostly the question |
| Two runs disagree, and neither is auditable | Same question, same SQL, same number |

The token effect is direct. Schema discovery is the bulk of a cold agent run. A semantic layer
replaces exploration with lookup.

## Sequencing an adoption

Do not build the whole cake before shipping anything. Take the three metrics that get asked
about most, and drive them all the way up.

1. Pick the three most-requested metrics.
2. Conform their sources into curated tables with declared grain and gate queries.
3. Define those three metrics in a semantic view, with synonyms.
4. Add verified queries for the ten questions people actually ask about them.
5. Point one agent at it. Ask the same question twenty times. Compare.
6. Widen only after step five is boring.

Step five is the acceptance test for the whole framework. If twenty runs of one question do
not agree, something below is still ambiguous.
