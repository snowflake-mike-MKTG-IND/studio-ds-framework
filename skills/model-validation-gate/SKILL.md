---
name: model-validation-gate
description: >
  Validation gate that must run before any model scoring, retraining, or
  publication of a predicted number. Refuses to proceed when inputs are wrong.
  Use for: before scoring, pre-score check, validate inputs, gate check, is the
  data ready, verify before publishing, model readiness. Triggers: validate
  before scoring, pre-score, gate check, model readiness, check the data, before
  I retrain, verify inputs.
---

# Model validation gate

This skill produces no analysis. It produces a verdict: PASS or STOP. Its value
is entirely in the runs where it says STOP.

Run the checks as SQL or scripts. Use this skill as an independent review subagent
when requested for high-risk work; independence does not require repeating every
deterministic query in a second LLM loop.

## Setup

Require the repo root or approved absolute check paths, target dataset, expected
source population, horizon, model requirements, and baseline acceptance thresholds.
Missing inputs mean STOP. Do not infer them from an account-wide scan.

## Verdict rules

- Any gate returning rows is a **STOP**. Report which gate, how many rows, and
  the identifying keys. Do not proceed to scoring.
- Errors, missing check files, disabled/skipped checks, or an unexpectedly empty
  source mean STOP, not PASS. Stop after two failed execution attempts.
- There is no partial pass. Do not offer to score "the clean subset" unless the
  caller explicitly asks after seeing the failure.
- Do not repair the data as part of this skill. Diagnosis and remediation are
  separate acts, and a gate that fixes what it finds stops being a measurement.

## Checks

Run the team's adapted and approved gate runner. `sql/50_validation_gates.sql`
is a starter containing setup DDL and incomplete analytical checks; do not run it
unchanged or label it a production gate. Its limitations are documented in
`docs/07_repeatability_gates.md`. Each implemented check returns rows only on failure.

| Gate | Defect | What a hit means |
|---|---|---|
| 1 | Missed dimension join | A record will be scored as "lowest", not "unknown" |
| 1b | Unmapped source key | Rows are silently dropped in the conform step |
| 2 | Fanout at grain | Sums inflated, averages deflated |
| 2b | Duplicate reference IDs | The usual cause of gate 2 |
| 3 | Dual-keyed double count | Every aggregate doubled |
| 4 | Point-in-time feature mismatch | Recomputed cutoff feature differs from the stored feature |
| 4b | Target in features | Label information is present in a predictor before it was knowable |
| 5 | Stale input | Pipeline reports healthy, inputs are frozen |
| 6 | Hindsight overwrite | Accuracy history is unfalsifiable |

Then check the model-specific items:

7. **Feature coverage.** Every feature the model expects is present and
   non-null for every row about to be scored. A missing feature imputed to zero
   is gate 1 wearing a different hat.

8. **Horizon consistency.** Rows about to be scored share one horizon, and that
   horizon is one the model was trained on.

9. **Accuracy plausibility.** If a retrain reports an error metric far better
   than the established baseline, treat that as a leakage bug report and STOP,
   not as a result. An unexplained jump in backtest accuracy is the most common
   symptom of gates 4 and 4b.

10. **Prediction of record.** If any title about to be scored already has a
    published prediction at this horizon, the existing one stands. A new score
    is appended with its own model version, never written over the old value.

## Output format

```
VERDICT: STOP

FAILED
  gate_1_missing_dimension     14 rows   TITLE_ID 1204, 1207, 1211, ...
  gate_5_stale_signal           3 rows   TITLE_ID 1219 (6 days behind)

PASSED
  gate_2, gate_2b, gate_3, gate_4, gate_4b, gate_6, checks 7-10

BLOCKING: 14 titles would score as lowest-demand rather than unknown.
NEXT: resolve the STUDIO_TIER join misses, then rerun this gate.
```

On a clean run, output `VERDICT: PASS`, the list of gates cleared, and the row
count validated. Nothing else.

## Adding a check

Every incident becomes a gate. When a wrong number reaches a stakeholder, write
the query that would have caught it, add it to
`sql/50_validation_gates.sql` with a comment naming the incident, and add a row
to the table above. The suite is the team's institutional memory in executable
form, and it is why the same defect does not ship twice.
