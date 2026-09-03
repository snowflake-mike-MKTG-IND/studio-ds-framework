-- 10_curated_feature_view.sql
-- An as-of-correct feature view. One row per (TITLE_ID, DAYS_OUT).
--
-- The pattern that matters: every aggregate is bounded by the cutoff date
-- implied by DAYS_OUT, so a row can only see data that existed at that point.
-- Percentiles are computed WITHIN a horizon, never across the full history.
--
-- Requires: sql/00_layer_contract.sql

CREATE OR REPLACE VIEW STUDIO_DS.CURATED.TITLE_FEATURES AS
WITH horizons AS (
    -- The horizons a model or report is allowed to ask about.
    SELECT h.VALUE::NUMBER AS DAYS_OUT
    FROM TABLE(FLATTEN(INPUT => ARRAY_CONSTRUCT(3, 7, 14, 21, 28))) h
),

-- One (title, horizon) spine row per horizon that has actually arrived.
spine AS (
    SELECT
        t.TITLE_ID,
        h.DAYS_OUT,
        t.RELEASE_DATE,
        DATEADD('day', -h.DAYS_OUT, t.RELEASE_DATE) AS AS_OF_DATE
    FROM STUDIO_DS.CURATED.TITLE t
    CROSS JOIN horizons h
    WHERE DATEADD('day', -h.DAYS_OUT, t.RELEASE_DATE) <= CURRENT_DATE()
),

-- Signal aggregates, bounded by AS_OF_DATE. This bound is the whole point.
signal AS (
    SELECT
        s.TITLE_ID,
        s.DAYS_OUT,
        AVG(CASE WHEN d.SIGNAL_DATE > DATEADD('day', -7, s.AS_OF_DATE)
                 THEN d.SIGNAL_VALUE END)                       AS SIGNAL_ROLLING_7,
        MAX(d.SIGNAL_VALUE)                                     AS SIGNAL_PEAK,
        COUNT(d.SIGNAL_VALUE)                                   AS SIGNAL_OBS,
        -- Slope over the trailing fortnight. Null when there is not enough history.
        REGR_SLOPE(d.SIGNAL_VALUE, DATEDIFF('day', s.AS_OF_DATE, d.SIGNAL_DATE))
            AS SIGNAL_SLOPE_14
    FROM spine s
    LEFT JOIN STUDIO_DS.CURATED.SIGNAL_DAILY d
           ON d.TITLE_ID    = s.TITLE_ID
          AND d.SIGNAL_DATE <= s.AS_OF_DATE            -- the cutoff
          AND d.SIGNAL_DATE >  DATEADD('day', -14, s.AS_OF_DATE)
    GROUP BY s.TITLE_ID, s.DAYS_OUT
),

joined AS (
    SELECT
        s.TITLE_ID,
        s.DAYS_OUT,
        s.RELEASE_DATE,
        s.AS_OF_DATE,
        t.GENRE,
        t.STUDIO_TIER,
        t.IS_SEQUEL,
        g.SIGNAL_ROLLING_7,
        g.SIGNAL_PEAK,
        g.SIGNAL_SLOPE_14,
        COALESCE(g.SIGNAL_OBS, 0) AS SIGNAL_OBS,
        -- Distinguish missing from zero. A model that cannot tell these apart
        -- will read "no data" as "no demand".
        CASE WHEN g.SIGNAL_ROLLING_7 IS NULL THEN 1 ELSE 0 END AS SIGNAL_MISSING,
        -- A dimension that failed to join is a defect, not a default. Flag it
        -- rather than substituting a value.
        CASE WHEN t.STUDIO_TIER IS NULL THEN 1 ELSE 0 END       AS STUDIO_TIER_MISSING
    FROM spine s
    JOIN STUDIO_DS.CURATED.TITLE t ON t.TITLE_ID = s.TITLE_ID
    LEFT JOIN signal g
           ON g.TITLE_ID = s.TITLE_ID
          AND g.DAYS_OUT = s.DAYS_OUT
)

SELECT
    j.*,
    -- Percentile WITHIN horizon. Comparing a 28-day-out reading against
    -- 3-day-out readings compares two different distributions.
    PERCENT_RANK() OVER (
        PARTITION BY j.DAYS_OUT
        ORDER BY j.SIGNAL_ROLLING_7 NULLS FIRST
    ) AS SIGNAL_PCTL_IN_HORIZON
FROM joined j;

-- ---------------------------------------------------------------------------
-- The look-ahead this view still contains, stated plainly.
--
-- PERCENT_RANK above ranks a title against every other title in the same
-- horizon, including titles that released later. For reporting on the past
-- that is fine. For training a model that will run on titles with no future,
-- it is leakage: the rank of a 2024 title is influenced by 2026 titles.
--
-- The strict variant restricts the comparison set to titles whose AS_OF_DATE
-- had already passed. It is slower and it is what a model should train on.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE VIEW STUDIO_DS.CURATED.TITLE_FEATURES_EXPANDING AS
SELECT
    f.*,
    (
        SELECT COUNT_IF(p.SIGNAL_ROLLING_7 < f.SIGNAL_ROLLING_7) / NULLIF(COUNT(*) - 1, 0)
        FROM STUDIO_DS.CURATED.TITLE_FEATURES p
        WHERE p.DAYS_OUT   =  f.DAYS_OUT
          AND p.AS_OF_DATE <= f.AS_OF_DATE      -- only what had happened by then
    ) AS SIGNAL_PCTL_EXPANDING
FROM STUDIO_DS.CURATED.TITLE_FEATURES f;
