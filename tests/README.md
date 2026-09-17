# Verification

## Local checks

From the repo root, run `node --test tests/repository.test.mjs` with Node.js 18+.
No package installation or Snowflake access is required. These tests check source
contracts, fixture alignment, approval predicates, current usage views, relative
Markdown links, and offline HTML structure. They do not execute Snowflake SQL.

## Read-only Snowflake checks

Run `enrichment_regression.sql`: all 12 key/version/rerun cases must return PASS.
Run `response_regression.sql`: all six response parsing cases must return PASS.
Both use synthetic VALUES and create no objects or model calls. The local tests
assert that their key and response predicates match the example implementation.

Compile the 11 independent statements in `sql/40_cost_observability.sql` using a
role that can read the referenced Account Usage views. Compilation validates syntax
and visible columns; it does not establish completeness of usage or attribution.

## Evidence from 2026-09-17

- 11 local repository tests passed; `git diff --check` passed.
- 12 Snowflake key/version fixtures and six response fixtures passed.
- All 11 cost-observability queries compiled against Snowflake.
- Both scoring function signatures compiled without executing inference.
- The two actual function token-estimation signatures ran on one synthetic text.
- A synthetic missing-prediction evaluation returned incomplete-coverage STOP and
  counted the missing prediction as a false negative.
- The corrected embedded revenue query returned its expected synthetic result.
- The local HTML rendered with all section headings present, no missing CSS classes,
  wrapped tables, and no detected text overflow at a 360-pixel body width.

## Not established by these tests

No permanent sample objects were deployed and no inference batch was executed.
The multi-statement setup/scoring/persistence sequence still requires a pilot in
the team's approved development database. Gold-set accuracy, actual savings,
concurrency handling, and full production gate readiness are not certified here.
Run the private measured exercise in `docs/09_measured_exercise.md` before adoption.
Rendered DOM checks are not a complete visual audit of every viewport/theme.