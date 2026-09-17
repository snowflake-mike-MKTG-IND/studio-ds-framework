# Measure incremental scoring

This exercise verifies whether reruns avoid unnecessary inference without losing
coverage or quality. Expected counts below are test criteria, **not measured savings**.
Use your team's approved development database and private test corpus. Do not deploy
these sample objects into a production or internal reporting account by default.

## Prepare

1. Adapt the `STUDIO_DS` prefix in a private copy after approving the destination.
2. Run [sql/00](../sql/00_layer_contract.sql) to create the sample namespaces, then
   [sql/30](../sql/30_incremental_ai_enrichment.sql) for setup and preflight only.
3. Load a small approved corpus into `RAW.TEXT_ITEM`. Use hashed author identifiers,
   not raw handles. An absent author is allowed; an absent title is excluded and must
   be reconciled. Text outside 8-2,000 characters is excluded, not silently truncated.
4. Run [tests/enrichment_regression.sql](../tests/enrichment_regression.sql) and
   [tests/response_regression.sql](../tests/response_regression.sql).
   Every result must be PASS. These use synthetic values and perform no inference.
5. Re-run sql/30 in one session to freeze at most 100 eligible candidates and their
   input-token estimates. Inspect the estimate and the candidates before approval.

## Approve and score

Keep the same session. Only after reviewing the candidate set and estimate, run
`SET SCORING_APPROVED = TRUE`, then [sql/31](../sql/31_score_approved_batch.sql).
The file resets approval after inference. Without approval it selects no rows for
model inference. The starter ceiling is an input-size guardrail, not a credit cap.
Changing a limit requires a fresh preflight and approval.

The two responses are persisted in a session temporary table before parsing and
merging into the permanent result table. Invalid or failed outputs become
`REVIEW_REQUIRED` and are not automatically retried. Fix the cause and explicitly
authorize a versioned retry; do not discard the history.

Run one writer at a time. Neither a standard-table key comment nor MERGE prevents
concurrent inference. Serialize the job before adopting this pattern. If the MERGE
fails, retry that statement using the retained response table, not the model call.
Losing the session between inference and persistence can still require paid rework.
Exactly-once billing is not claimed.

## Test four changes

| Scenario | Expected new work | What to verify |
|---|---|---|
| First approved batch | All selected, previously unseen input/version pairs | Every attempt is stored as succeeded or review-required; reconcile exclusions |
| Unchanged rerun | None of the already attempted pairs | With more than 100 pending items, the next batch can legitimately contain other records; test a corpus of at most 100 for an empty rerun |
| Changed input | Only changed/new content pairs | Old results remain as history; the current-source aggregate joins only the current eligible content |
| Changed prompt/configuration or model policy | The selected pairs under the new scorer version | Old versions remain; current reporting and evaluation use one selected scorer version |

The hash includes a typed array of title, author hash, and text, preserving nulls and
separators. It is a business-tuple policy: identical text from different authors counts
as separate records. If the task permits caching across authors, separate the inference
cache key from the event key so you do not erase real events while saving inference.
Dates do not affect this example's classification; include them in the key if they
become model context. Treat the source as a current snapshot for edits, or resolve the
latest source revision before deduplication; an append-only source retains old text.

The scorer hash includes the pipeline version, model policy, labels, and task/output
configuration. Bump the pipeline version when preprocessing, extraction, category
semantics, or unrepresented options change. The managed functions do not pin a public
underlying model version: `MODEL_POLICY` documents the selected function policy, not
an invented model ID. Revalidate after service changes and version deliberate rescoring.

## Measure quality and cost

Populate `OPS.INTENT_GOLD` with one human-labeled row per item hash, covering every
supported class. Run [sql/32](../sql/32_enrichment_quality.sql). Duplicate keys or invalid
labels invalidate the evaluation. Missing predictions count as false negatives;
missing class support or incomplete coverage blocks acceptance. Set the required
per-class precision/recall and macro F1 before comparing configurations. Do not tune
and report on the same holdout set.

Each scoring run exposes its run ID and query ID. After telemetry has arrived, use
[sql/41](../sql/41_enrichment_run_cost.sql) for scoring credits per 1,000 validated
items. “Validated” here means well-formed output, not human-confirmed correctness.
Record gold-set quality separately. The query leaves absent usage as unknown and is
not a full pipeline bill: add run-tagged preparation, persistence, failed/orphaned
queries, and an explicit idle-cost allocation if reporting all-in cost.

For the unchanged empty rerun, verify zero candidates and no inference records after
the telemetry delay. Record the small preparation/SQL cost separately. Do not report
an undefined cost per zero output records as zero. Use the CoCo usage queries to
measure the development-session cost separately from the production batch.

Keep a private result ledger with: scenario, run/query IDs, scorer version, eligible,
excluded, attempted, validated and review counts, input estimate, actual AI credits,
attributed warehouse credits, quality metrics, telemetry completeness, and acceptance.
No client values or account identifiers belong in this public repo.

## Existing installations

This revision creates `TEXT_ENRICHMENT_RESULT` rather than altering or deleting the
older `TEXT_ITEM_SCORED`. It does not reuse old rows automatically because their hash
and version semantics differ. Review migration, mapping, and rescore cost first.
Simply running the new preflight does not spend inference tokens. The sample schemas
remain a starter contract, not a migration of your production pipeline.