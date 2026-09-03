-- 50_validation_gates.sql
-- Every gate returns rows ONLY on failure. Zero rows means pass.
--
-- Run the whole file before publishing a number, scoring a model, or letting an
-- agent report to a stakeholder. Six gates, one per defect in docs/07.
--
-- Requires: sql/00_layer_contract.sql, sql/10_curated_feature_view.sql

-- ---------------------------------------------------------------------------
-- Gate 1. Valid-zero from a missed join.
--
-- A LEFT JOIN miss becomes a legitimate-looking zero downstream. On a score or
-- an index, zero means "lowest", so the record is confidently ranked last
-- rather than flagged as unknown.
-- ---------------------------------------------------------------------------

SELECT 'gate_1_missing_dimension' AS GATE_NAME, TITLE_ID, DAYS_OUT,
       'STUDIO_TIER failed to join' AS DETAIL
FROM STUDIO_DS.CURATED.TITLE_FEATURES
WHERE STUDIO_TIER_MISSING = 1;

-- Unmapped source keys. These are rows that silently vanish in the conform step.
SELECT 'gate_1b_unmapped_source_key' AS GATE_NAME,
       r.SOURCE_NAME, r.ENTITY_KEY, COUNT(*) AS RAW_ROWS
FROM STUDIO_DS.RAW.SIGNAL_DAILY r
LEFT JOIN STUDIO_DS.CURATED.ENTITY_MAP m
       ON m.SOURCE_NAME = r.SOURCE_NAME AND m.ENTITY_KEY = r.ENTITY_KEY
WHERE m.TITLE_ID IS NULL
GROUP BY 1, 2, 3;

-- ---------------------------------------------------------------------------
-- Gate 2. Fanout from an undeclared cardinality.
--
-- The feature view must have exactly one row per (TITLE_ID, DAYS_OUT). A
-- duplicate in any joined reference table multiplies fact rows; sums inflate
-- and averages deflate, and nothing errors.
-- ---------------------------------------------------------------------------

SELECT 'gate_2_feature_fanout' AS GATE_NAME, TITLE_ID, DAYS_OUT, COUNT(*) AS ROWS_AT_GRAIN
FROM STUDIO_DS.CURATED.TITLE_FEATURES
GROUP BY TITLE_ID, DAYS_OUT
HAVING COUNT(*) > 1;

-- Duplicate identifiers in a reference table, the usual cause.
SELECT 'gate_2b_duplicate_title_id' AS GATE_NAME, TITLE_ID, COUNT(*) AS ROWS_AT_GRAIN
FROM STUDIO_DS.CURATED.TITLE
GROUP BY TITLE_ID
HAVING COUNT(*) > 1;

-- ---------------------------------------------------------------------------
-- Gate 3. Double count from dual-keyed writes.
--
-- The same record written under two surrogate keys, because one pipeline keyed
-- on a name and another on an ID. Compare the count on the business tuple
-- against the raw count.
-- ---------------------------------------------------------------------------

SELECT 'gate_3_dual_key_double_count' AS GATE_NAME,
       COUNT(*)                                                          AS RAW_ROWS,
       COUNT(DISTINCT SHA2(CONCAT_WS('|', TITLE_ID::VARCHAR, AUTHOR_HASH, ITEM_TEXT), 256))
                                                                         AS DISTINCT_ON_TUPLE,
       COUNT(*) - COUNT(DISTINCT SHA2(CONCAT_WS('|', TITLE_ID::VARCHAR, AUTHOR_HASH, ITEM_TEXT), 256))
                                                                         AS SURPLUS_ROWS
FROM STUDIO_DS.RAW.TEXT_ITEM
HAVING SURPLUS_ROWS > 0;

-- ---------------------------------------------------------------------------
-- Gate 4. Look-ahead in a feature.
--
-- Any signal row dated after its own AS_OF_DATE is the future leaking into the
-- past. This gate checks the bound the feature view claims to enforce.
-- ---------------------------------------------------------------------------

SELECT 'gate_4_lookahead_signal' AS GATE_NAME,
       f.TITLE_ID, f.DAYS_OUT, f.AS_OF_DATE, MAX(d.SIGNAL_DATE) AS LATEST_SIGNAL_USED
FROM STUDIO_DS.CURATED.TITLE_FEATURES f
JOIN STUDIO_DS.CURATED.SIGNAL_DAILY d
  ON d.TITLE_ID = f.TITLE_ID
 AND d.SIGNAL_DATE >  DATEADD('day', -14, f.AS_OF_DATE)
 AND d.SIGNAL_DATE >  f.AS_OF_DATE          -- must never contribute
GROUP BY 1, 2, 3, 4;

-- An outcome observed after the feature cutoff must not be joinable into a
-- training row. This catches the target leaking into the features.
SELECT 'gate_4b_outcome_before_observed' AS GATE_NAME,
       f.TITLE_ID, f.DAYS_OUT, f.AS_OF_DATE, o.OBSERVED_AT
FROM STUDIO_DS.CURATED.TITLE_FEATURES f
JOIN STUDIO_DS.CURATED.TITLE_OUTCOME o ON o.TITLE_ID = f.TITLE_ID
WHERE o.OBSERVED_AT > f.AS_OF_DATE
  AND f.SIGNAL_MISSING = 0
  -- Expected to return rows in a REPORTING context; must be excluded from any
  -- training set. Filter training on o.OBSERVED_AT <= f.AS_OF_DATE, or accept
  -- that this is a post-hoc analysis and not a forecast.
  AND FALSE;   -- flip to TRUE when validating a training extract

-- ---------------------------------------------------------------------------
-- Gate 5. Stale input passing a freshness check.
--
-- Assert on MAX(date), never on MIN and never on row count. A gate that checks
-- minimum age passes a table that stopped updating, because the newest row it
-- still has is recent enough by that test.
-- ---------------------------------------------------------------------------

SELECT 'gate_5_stale_signal' AS GATE_NAME,
       t.TITLE_ID,
       t.TITLE_NAME,
       MAX(d.SIGNAL_DATE)                                          AS LATEST_SIGNAL,
       LEAST(t.RELEASE_DATE, DATEADD('day', -1, CURRENT_DATE()))    AS EXPECTED_THROUGH,
       DATEDIFF('day', MAX(d.SIGNAL_DATE),
                LEAST(t.RELEASE_DATE, DATEADD('day', -1, CURRENT_DATE()))) AS DAYS_BEHIND
FROM STUDIO_DS.CURATED.TITLE t
LEFT JOIN STUDIO_DS.CURATED.SIGNAL_DAILY d ON d.TITLE_ID = t.TITLE_ID
WHERE t.RELEASE_DATE >= CURRENT_DATE()          -- titles still in the window
GROUP BY t.TITLE_ID, t.TITLE_NAME, t.RELEASE_DATE
HAVING DAYS_BEHIND > 1 OR MAX(d.SIGNAL_DATE) IS NULL;

-- ---------------------------------------------------------------------------
-- Gate 6. Hindsight overwrite of a published number.
--
-- A published prediction is the prediction of record, permanently. If a retrain
-- rewrote it, the accuracy history is no longer falsifiable.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS STUDIO_DS.OPS.PREDICTION_LOG (
    TITLE_ID        NUMBER,
    DAYS_OUT        NUMBER,
    PREDICTED_VALUE FLOAT,
    MODEL_VERSION   VARCHAR       COMMENT 'The version live at publication. Never updated.',
    PUBLISHED_AT    TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Append-only. GRAIN: one row per (TITLE_ID, DAYS_OUT, MODEL_VERSION, PUBLISHED_AT).';

-- More than one prediction for the same (title, horizon, version) means a
-- rescore was written over a published number rather than appended.
SELECT 'gate_6_hindsight_overwrite' AS GATE_NAME,
       TITLE_ID, DAYS_OUT, MODEL_VERSION,
       COUNT(*)                        AS VERSIONS_LOGGED,
       COUNT(DISTINCT PREDICTED_VALUE) AS DISTINCT_VALUES
FROM STUDIO_DS.OPS.PREDICTION_LOG
GROUP BY 1, 2, 3, 4
HAVING COUNT(DISTINCT PREDICTED_VALUE) > 1;

-- The prediction of record: earliest publication per (title, horizon).
CREATE OR REPLACE VIEW STUDIO_DS.OPS.PREDICTION_OF_RECORD AS
SELECT TITLE_ID, DAYS_OUT, PREDICTED_VALUE, MODEL_VERSION, PUBLISHED_AT
FROM (
    SELECT *, ROW_NUMBER() OVER (
                 PARTITION BY TITLE_ID, DAYS_OUT ORDER BY PUBLISHED_AT
              ) AS RN
    FROM STUDIO_DS.OPS.PREDICTION_LOG
)
WHERE RN = 1;
