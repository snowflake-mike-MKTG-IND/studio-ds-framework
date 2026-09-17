-- 20_semantic_view.sql
-- The semantic layer. This is the interface an agent, a dashboard, and Cortex
-- Analyst all consume. Nothing above this layer writes its own aggregation.
--
-- Requires: sql/00_layer_contract.sql, sql/10_curated_feature_view.sql

CREATE OR REPLACE SEMANTIC VIEW STUDIO_DS.SEMANTIC.TITLE_PERFORMANCE

  TABLES (
    titles AS STUDIO_DS.CURATED.TITLE
      PRIMARY KEY (TITLE_ID)
      WITH SYNONYMS ('films', 'movies', 'releases', 'slate')
      COMMENT = 'One row per title. The spine of every question about a release.',

    features AS STUDIO_DS.CURATED.TITLE_FEATURES
      PRIMARY KEY (TITLE_ID, DAYS_OUT)
      WITH SYNONYMS ('demand signals', 'pre-release signals')
      COMMENT = 'As-of-correct signal features. One row per title and horizon.',

    outcomes AS STUDIO_DS.CURATED.TITLE_OUTCOME
      PRIMARY KEY (TITLE_ID, OUTCOME_NAME)
      WITH SYNONYMS ('results', 'actuals')
      COMMENT = 'Observed outcomes. Only known after OBSERVED_AT.'
  )

  RELATIONSHIPS (
    -- Declared cardinality. This is what prevents a silent fanout.
    features_to_titles AS features (TITLE_ID) REFERENCES titles,
    outcomes_to_titles AS outcomes (TITLE_ID) REFERENCES titles
  )

  FACTS (
    features.f_signal_rolling  AS SIGNAL_ROLLING_7
      COMMENT = 'Trailing seven-day mean of the demand signal as of the horizon.',
    features.f_signal_pctl     AS SIGNAL_PCTL_IN_HORIZON
      COMMENT = 'Percentile within the same horizon. Not comparable across horizons.',
    outcomes.f_outcome_value   AS OUTCOME_VALUE
  )

  DIMENSIONS (
    titles.title_name    AS TITLE_NAME
      WITH SYNONYMS = ('film', 'movie', 'name'),
    titles.release_date  AS RELEASE_DATE,
    titles.release_year  AS YEAR(RELEASE_DATE)
      WITH SYNONYMS = ('year'),
    titles.genre         AS GENRE
      WITH SYNONYMS = ('category'),
    titles.studio_tier   AS STUDIO_TIER
      WITH SYNONYMS = ('studio size', 'distributor tier')
      SAMPLE_VALUES ('MAJOR', 'MID', 'INDIE')
      IS_ENUM,
    titles.is_sequel     AS IS_SEQUEL
      WITH SYNONYMS = ('sequel', 'franchise entry'),
    features.days_out    AS DAYS_OUT
      WITH SYNONYMS = ('horizon', 'days before release', 'lead time')
      COMMENT = 'Days before release the features were computed. Always filter on one horizon.',
    outcomes.outcome_name AS OUTCOME_NAME
      SAMPLE_VALUES ('OPENING_REVENUE')
      IS_ENUM
  )

  METRICS (
    titles.m_title_count          AS COUNT(TITLE_ID)
      WITH SYNONYMS = ('number of titles', 'how many films')
      COMMENT = 'Count of titles.',
    outcomes.m_total_outcome      AS SUM(outcomes.f_outcome_value)
      WITH SYNONYMS = ('total revenue', 'total gross', 'total box office')
      COMMENT = 'Sum of the observed outcome. Filter OUTCOME_NAME or this mixes measures.',
    outcomes.m_avg_outcome        AS AVG(outcomes.f_outcome_value)
      WITH SYNONYMS = ('average revenue', 'average gross'),
    features.m_avg_signal         AS AVG(features.f_signal_rolling)
      WITH SYNONYMS = ('average demand', 'mean signal'),
    features.m_avg_signal_pctl    AS AVG(features.f_signal_pctl)
      WITH SYNONYMS = ('average demand percentile')
  )

  COMMENT = 'Title performance. The single definition of every standing metric.'

  -- Custom instructions. These remove the interpretive latitude that otherwise
  -- shows up as two different answers to the same question.
  AI_SQL_GENERATION
    'Always filter FEATURES.DAYS_OUT to a single horizon; features are not
     comparable across horizons. Always filter OUTCOMES.OUTCOME_NAME to a single
     measure. Round currency to whole dollars.'

  AI_QUESTION_CATEGORIZATION
    'If a question about demand signals does not specify a horizon, treat it as
     UNCLEAR and ask which horizon (3, 7, 14, 21, or 28 days before release).'

  -- Verified examples guide SQL generation; they are not cached results.
  -- Validate the embedded SQL independently before registering the examples.
  AI_VERIFIED_QUERIES (

    total_by_year AS (
      QUESTION 'What was total opening revenue by release year?'
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = data_stewards)'
      SQL 'SELECT YEAR(t.RELEASE_DATE) AS release_year, SUM(o.OUTCOME_VALUE) AS total_outcome
             FROM STUDIO_DS.CURATED.TITLE_OUTCOME o
             JOIN STUDIO_DS.CURATED.TITLE t ON t.TITLE_ID = o.TITLE_ID
            WHERE o.OUTCOME_NAME = ''OPENING_REVENUE''
            GROUP BY 1 ORDER BY 1 DESC'
    ),

    demand_at_7_days AS (
      QUESTION 'Which titles have the highest demand signal seven days out?'
      ONBOARDING_QUESTION TRUE
      VERIFIED_BY '(STEWARD = data_stewards)'
      SQL 'SELECT t.TITLE_NAME, f.SIGNAL_ROLLING_7, f.SIGNAL_PCTL_IN_HORIZON
             FROM STUDIO_DS.CURATED.TITLE_FEATURES f
             JOIN STUDIO_DS.CURATED.TITLE t ON t.TITLE_ID = f.TITLE_ID
            WHERE f.DAYS_OUT = 7 AND f.SIGNAL_MISSING = 0
            ORDER BY f.SIGNAL_ROLLING_7 DESC NULLS LAST'
    )
  );

-- Query it. Note that the caller names metrics and dimensions, never columns.
--
-- SELECT * FROM SEMANTIC_VIEW(
--   STUDIO_DS.SEMANTIC.TITLE_PERFORMANCE
--   METRICS    outcomes.m_avg_outcome
--   DIMENSIONS titles.release_year, titles.studio_tier
-- );

-- Agents need REFERENCES in addition to SELECT.
-- GRANT REFERENCES, SELECT ON SEMANTIC VIEW STUDIO_DS.SEMANTIC.TITLE_PERFORMANCE
--   TO ROLE <agent_role>;
