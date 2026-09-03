-- 00_layer_contract.sql
-- Schema conventions for the four layers. Adapt names; keep the boundaries.
--
-- Rule: each layer reads only the layer directly below it.
--   RAW      -> landed source data, append-only
--   CURATED  -> conformed, deduplicated, declared grain
--   SEMANTIC -> semantic views, the interface for questions
--   OPS      -> gate results, cost rollups, run logs

CREATE DATABASE IF NOT EXISTS STUDIO_DS;

CREATE SCHEMA IF NOT EXISTS STUDIO_DS.RAW      COMMENT = 'Landed source data. Append-only. No consumer reads this directly.';
CREATE SCHEMA IF NOT EXISTS STUDIO_DS.CURATED  COMMENT = 'Conformed tables. Every object declares its grain.';
CREATE SCHEMA IF NOT EXISTS STUDIO_DS.SEMANTIC COMMENT = 'Semantic views. The only interface agents and dashboards use.';
CREATE SCHEMA IF NOT EXISTS STUDIO_DS.OPS      COMMENT = 'Validation gate results, cost rollups, run logs.';

-- ---------------------------------------------------------------------------
-- RAW. One table per source. Never edited in place, never joined by consumers.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS STUDIO_DS.RAW.SIGNAL_DAILY (
    ENTITY_KEY      VARCHAR        COMMENT 'Source-side identifier, as delivered',
    SIGNAL_NAME     VARCHAR        COMMENT 'Which measure this row carries',
    SIGNAL_DATE     DATE,
    SIGNAL_VALUE    FLOAT,
    SOURCE_NAME     VARCHAR        COMMENT 'Which provider delivered this row',
    LOADED_AT       TIMESTAMP_LTZ  DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'GRAIN: not enforced. Raw may contain duplicates by design.';

-- ---------------------------------------------------------------------------
-- CURATED. Grain is declared in the comment and enforced by a gate query.
-- Surrogate keys are internal; the business tuple is what dedupe runs on.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS STUDIO_DS.CURATED.TITLE (
    TITLE_ID        NUMBER         COMMENT 'Internal surrogate key',
    TITLE_NAME      VARCHAR,
    RELEASE_DATE    DATE,
    GENRE           VARCHAR,
    IS_SEQUEL       BOOLEAN,
    STUDIO_TIER     VARCHAR        COMMENT 'MAJOR | MID | INDIE. Never defaulted on a join miss.'
)
COMMENT = 'GRAIN: one row per TITLE_ID.';

CREATE TABLE IF NOT EXISTS STUDIO_DS.CURATED.SIGNAL_DAILY (
    TITLE_ID        NUMBER,
    SIGNAL_NAME     VARCHAR,
    SIGNAL_DATE     DATE,
    SIGNAL_VALUE    FLOAT,
    SOURCE_NAME     VARCHAR
)
COMMENT = 'GRAIN: one row per (TITLE_ID, SIGNAL_NAME, SIGNAL_DATE). Deduped on that tuple, not on any surrogate key.';

CREATE TABLE IF NOT EXISTS STUDIO_DS.CURATED.TITLE_OUTCOME (
    TITLE_ID        NUMBER,
    OUTCOME_NAME    VARCHAR        COMMENT 'e.g. OPENING_REVENUE',
    OUTCOME_VALUE   FLOAT,
    OBSERVED_AT     DATE           COMMENT 'When the outcome became known. Nothing before this date may use it.'
)
COMMENT = 'GRAIN: one row per (TITLE_ID, OUTCOME_NAME).';

-- The mapping table is the seam where source keys become internal keys.
-- Keep it explicit. An unmapped source key must surface as a gate failure,
-- never as a silently dropped row.
CREATE TABLE IF NOT EXISTS STUDIO_DS.CURATED.ENTITY_MAP (
    SOURCE_NAME     VARCHAR,
    ENTITY_KEY      VARCHAR,
    TITLE_ID        NUMBER
)
COMMENT = 'GRAIN: one row per (SOURCE_NAME, ENTITY_KEY).';

-- Conform RAW into CURATED. Dedupe on the business tuple. Keep the latest load.
CREATE OR REPLACE VIEW STUDIO_DS.CURATED.SIGNAL_DAILY_CONFORMED AS
SELECT TITLE_ID, SIGNAL_NAME, SIGNAL_DATE, SIGNAL_VALUE, SOURCE_NAME
FROM (
    SELECT
        m.TITLE_ID,
        r.SIGNAL_NAME,
        r.SIGNAL_DATE,
        r.SIGNAL_VALUE,
        r.SOURCE_NAME,
        ROW_NUMBER() OVER (
            PARTITION BY m.TITLE_ID, r.SIGNAL_NAME, r.SIGNAL_DATE
            ORDER BY r.LOADED_AT DESC
        ) AS RN
    FROM STUDIO_DS.RAW.SIGNAL_DAILY r
    JOIN STUDIO_DS.CURATED.ENTITY_MAP m
      ON m.SOURCE_NAME = r.SOURCE_NAME
     AND m.ENTITY_KEY  = r.ENTITY_KEY
)
WHERE RN = 1;

-- ---------------------------------------------------------------------------
-- OPS. Gate results are data. Store them so a trend in failures is visible.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS STUDIO_DS.OPS.GATE_RESULT (
    RUN_AT          TIMESTAMP_LTZ  DEFAULT CURRENT_TIMESTAMP(),
    GATE_NAME       VARCHAR,
    FAILING_ROWS    NUMBER,
    PASSED          BOOLEAN,
    DETAIL          VARIANT
)
COMMENT = 'GRAIN: one row per (RUN_AT, GATE_NAME).';
