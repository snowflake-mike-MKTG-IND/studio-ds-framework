-- 30_incremental_ai_enrichment.sql
-- Score each row with a model exactly once. A rerun touches only new rows.
--
-- This is the single largest cost lever in the stack. A pipeline that
-- re-classifies its whole corpus on every run has cost proportional to
-- total data times run frequency. This one has cost proportional to new data.

-- ---------------------------------------------------------------------------
-- 1. The corpus, deduplicated on the BUSINESS tuple.
--
-- The trap: the same text arriving under two surrogate keys, because one
-- pipeline keyed on a name and another on an ID. Dedupe on content, or you
-- pay twice to score it and then double-count the result.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS STUDIO_DS.RAW.TEXT_ITEM (
    ITEM_KEY     VARCHAR       COMMENT 'Source-side key. Not trusted for dedupe.',
    TITLE_ID     NUMBER,
    AUTHOR_HASH  VARCHAR       COMMENT 'Hashed at ingest. Never store raw handles.',
    ITEM_TEXT    VARCHAR,
    ITEM_DATE    DATE,
    LOADED_AT    TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE VIEW STUDIO_DS.CURATED.TEXT_ITEM_DEDUPED AS
SELECT
    -- The business tuple, hashed into a stable scoring key.
    SHA2(CONCAT_WS('|', TITLE_ID::VARCHAR, AUTHOR_HASH, ITEM_TEXT), 256) AS ITEM_HASH,
    TITLE_ID,
    AUTHOR_HASH,
    ITEM_TEXT,
    MIN(ITEM_DATE) AS ITEM_DATE
FROM STUDIO_DS.RAW.TEXT_ITEM
WHERE ITEM_TEXT IS NOT NULL
  AND LENGTH(ITEM_TEXT) BETWEEN 8 AND 2000   -- filter BEFORE the model sees it
GROUP BY 1, 2, 3, 4;

-- ---------------------------------------------------------------------------
-- 2. The scored table. Append-only, keyed on ITEM_HASH.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS STUDIO_DS.CURATED.TEXT_ITEM_SCORED (
    ITEM_HASH    VARCHAR,
    TITLE_ID     NUMBER,
    ITEM_DATE    DATE,
    SENTIMENT    VARCHAR,
    INTENT       VARCHAR,
    MODEL_NAME   VARCHAR       COMMENT 'Which model produced this label. Required for any model swap.',
    SCORED_AT    TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'GRAIN: one row per (ITEM_HASH, MODEL_NAME).';

-- ---------------------------------------------------------------------------
-- 3. Estimate before you spend. Run this first, every time.
-- ---------------------------------------------------------------------------

WITH unscored AS (
    SELECT d.ITEM_TEXT
    FROM STUDIO_DS.CURATED.TEXT_ITEM_DEDUPED d
    LEFT JOIN STUDIO_DS.CURATED.TEXT_ITEM_SCORED s ON s.ITEM_HASH = d.ITEM_HASH
    WHERE s.ITEM_HASH IS NULL
)
SELECT
    COUNT(*)                                                    AS ROWS_TO_SCORE,
    SUM(AI_COUNT_TOKENS('claude-3-5-haiku', ITEM_TEXT))         AS INPUT_TOKENS_EST,
    AVG(AI_COUNT_TOKENS('claude-3-5-haiku', ITEM_TEXT))         AS AVG_TOKENS_PER_ROW
FROM unscored;

-- ---------------------------------------------------------------------------
-- 4. Score only what is unscored. The anti-join is the whole mechanism.
--
-- Two cost choices worth noticing:
--   AI_SENTIMENT is a fixed-purpose function, cheaper than a general
--   completion doing the same job.
--   The intent prompt asks for a bare label. Asking the model to explain its
--   label multiplies output tokens for something no aggregate consumes.
-- ---------------------------------------------------------------------------

INSERT INTO STUDIO_DS.CURATED.TEXT_ITEM_SCORED
    (ITEM_HASH, TITLE_ID, ITEM_DATE, SENTIMENT, INTENT, MODEL_NAME)
WITH unscored AS (
    SELECT d.*
    FROM STUDIO_DS.CURATED.TEXT_ITEM_DEDUPED d
    LEFT JOIN STUDIO_DS.CURATED.TEXT_ITEM_SCORED s ON s.ITEM_HASH = d.ITEM_HASH
    WHERE s.ITEM_HASH IS NULL
    LIMIT 50000                     -- bound every batch; never run unbounded
)
SELECT
    ITEM_HASH,
    TITLE_ID,
    ITEM_DATE,
    AI_SENTIMENT(ITEM_TEXT):categories[0]:sentiment::VARCHAR AS SENTIMENT,
    AI_CLASSIFY(
        ITEM_TEXT,
        ['WILL_ATTEND', 'INTERESTED', 'WILL_NOT_ATTEND', 'OFF_TOPIC']
    ):labels[0]::VARCHAR                                     AS INTENT,
    'ai_classify_default'                                    AS MODEL_NAME
FROM unscored;

-- ---------------------------------------------------------------------------
-- 5. Aggregate the labels in SQL. This is where counting happens, not in a
--    retrieval call and not in an agent loop.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW STUDIO_DS.CURATED.TEXT_SENTIMENT_BY_TITLE AS
SELECT
    TITLE_ID,
    ITEM_DATE,
    COUNT(*)                                                     AS ITEMS,
    COUNT_IF(SENTIMENT = 'positive') / NULLIF(COUNT(*), 0)       AS POSITIVE_SHARE,
    COUNT_IF(INTENT    = 'WILL_ATTEND') / NULLIF(COUNT(*), 0)    AS ATTEND_INTENT_SHARE
FROM STUDIO_DS.CURATED.TEXT_ITEM_SCORED
GROUP BY 1, 2;

-- ---------------------------------------------------------------------------
-- 6. Before swapping to a cheaper model, measure it. A labeled gold set and a
--    macro F1 is the only thing that makes a downgrade a decision rather than
--    a guess. Without it, the failure is quiet.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS STUDIO_DS.OPS.INTENT_GOLD (
    ITEM_HASH    VARCHAR,
    ITEM_TEXT    VARCHAR,
    TRUE_INTENT  VARCHAR       COMMENT 'Human-labeled. Stratified across classes.',
    LABELED_BY   VARCHAR,
    LABELED_AT   TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'GRAIN: one row per ITEM_HASH. Aim for a few hundred rows, class-stratified.';

WITH scored AS (
    SELECT g.ITEM_HASH, g.TRUE_INTENT, s.INTENT AS PRED_INTENT
    FROM STUDIO_DS.OPS.INTENT_GOLD g
    JOIN STUDIO_DS.CURATED.TEXT_ITEM_SCORED s ON s.ITEM_HASH = g.ITEM_HASH
),
per_class AS (
    SELECT
        c.CLASS_NAME,
        COUNT_IF(s.PRED_INTENT = c.CLASS_NAME AND s.TRUE_INTENT = c.CLASS_NAME) AS TP,
        COUNT_IF(s.PRED_INTENT = c.CLASS_NAME AND s.TRUE_INTENT <> c.CLASS_NAME) AS FP,
        COUNT_IF(s.PRED_INTENT <> c.CLASS_NAME AND s.TRUE_INTENT = c.CLASS_NAME) AS FN
    FROM (SELECT DISTINCT TRUE_INTENT AS CLASS_NAME FROM STUDIO_DS.OPS.INTENT_GOLD) c
    CROSS JOIN scored s
    GROUP BY 1
)
SELECT
    CLASS_NAME,
    DIV0(TP, TP + FP)                                    AS PRECISION,
    DIV0(TP, TP + FN)                                    AS RECALL,
    DIV0(2 * TP, 2 * TP + FP + FN)                       AS F1,
    AVG(DIV0(2 * TP, 2 * TP + FP + FN)) OVER ()          AS MACRO_F1
FROM per_class
ORDER BY CLASS_NAME;
