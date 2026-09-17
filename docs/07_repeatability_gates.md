# Repeatability gates

Six defects that pass every unit test, raise no error, and ship a wrong number. Each one is
worth a standing gate query. All six are checkable in SQL; `sql/50_validation_gates.sql`
implements them.

## 1. Valid-zero from a missed join

A `LEFT JOIN` that finds no match yields null, and a `COALESCE(x, 0)` downstream turns that
into a legitimate-looking zero. On a score or an index, zero means "lowest observed", so the
record is not flagged as unknown, it is confidently ranked last. Whole cohorts get suppressed
this way.

**Gate:** for every dimension table joined into a feature set, count the rows that failed to
match. Expected is a known number, usually zero. Any increase is the defect.

## 2. Fanout from an undeclared cardinality

A join to a table with more rows per key than expected multiplies the fact rows. Sums inflate,
averages deflate, and the row count is the only visible symptom. Duplicate identifiers in a
reference table are a common cause, and they arrive without warning when a source is updated.

**Gate:** assert the row count of the feature view equals the row count of its base grain.

## 3. Double count from dual-keyed writes

The same record written under two different keys, because one pipeline keyed on a name and
another on an ID. Both look correct in isolation. Together they double every aggregate.

**Gate:** count distinct on the business tuple, ignoring surrogate keys, and compare to the
raw row count.

## 4. Look-ahead in a normalization

Percentiles, ranks, and z-scores computed across the full history and then joined back to
historical rows. Every past record now carries information about its future. Backtest accuracy
improves, production accuracy does not, and the gap is not visible until the model is live.

**Gate:** recompute one historical row's features using only data available at its cutoff and
assert they match the stored values.

## 5. Stale input passing a freshness check

A freshness gate that checks minimum age rather than maximum date will pass a table that
stopped updating, because the newest row it has is still recent enough by that test. The
pipeline reports healthy and the inputs are frozen.

**Gate:** compare `MAX(load_date)` against the expected as-of date. Never assert on
`MIN`, and never assert on row count alone.

## 6. Hindsight overwrite of a published number

A model retrain rescoring a prediction that has already been published. The stored record now
shows what the current model would have said, not what was actually forecast, and the accuracy
history becomes unfalsifiable.

**Gate:** predictions are append-only, versioned, and stamped with the model version live at
publication. The prediction of record is the one that was published, permanently.

## How to run gates

Three properties matter more than the specific checks.

**A gate returns rows only on failure.** Zero rows means pass. This makes the whole suite one
query per check and trivially automatable.

**A gate blocks.** A warning that gets read and proceeded past is documentation, not a gate. In
an agent workflow this means the gate skill's failure path is stop-and-report, with no fallback
that continues.

**Execute checks deterministically.** Run SQL/scripts and require a blocking result before
publication. Use an independent reviewer for high-risk interpretation, not a new agent
for every routine assertion. Errors, skipped checks, missing files, and an unexpectedly
empty source are STOP or NOT VALIDATED, never PASS.

## Scope of these examples

`sql/50_validation_gates.sql` is an analytical starter, not a production gate runner.
It includes setup DDL and assumes adapted `sql/00`, `sql/10`, and the text table in
`sql/30`. Gate 4 checks whether later-dated source rows exist; it does not establish
which rows a feature actually used. Gate 4b is disabled by `AND FALSE` and requires a
training-specific implementation. Future outcomes are valid labels for historical
training examples, not valid pre-cutoff features. Gate 6 detects multiple recorded
values, not an UPDATE that erased the prior row. Protect and snapshot the prediction
history separately. Do not promote these checks unchanged or claim they certify a model.

The enrichment-specific checks in `sql/32_enrichment_quality.sql` and read-only
`tests/enrichment_regression.sql` cover the token-efficiency example. They do not
replace point-in-time feature validation or a complete production gate runner.

## Adding to the suite

Every incident becomes a gate. When a wrong number reaches a stakeholder, the remediation is
not only the fix, it is the query that would have caught it, added to the suite with a comment
naming the incident. The suite is the team's institutional memory in executable form, and it is
the reason the same defect does not ship twice.
