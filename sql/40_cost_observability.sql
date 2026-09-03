-- 40_cost_observability.sql
-- Token and warehouse spend, by workload. Read-only against SNOWFLAKE.ACCOUNT_USAGE.
--
-- Requires IMPORTED PRIVILEGES on the SNOWFLAKE database (ACCOUNTADMIN grants it).
-- ACCOUNT_USAGE views lag by roughly 45 minutes to three hours.

-- ---------------------------------------------------------------------------
-- 1. The two meters, side by side, by day. Start here.
-- ---------------------------------------------------------------------------

WITH tokens AS (
    SELECT DATE_TRUNC('day', START_TIME) AS D, SUM(TOKEN_CREDITS) AS TOKEN_CREDITS
    FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_FUNCTIONS_USAGE_HISTORY
    WHERE START_TIME >= DATEADD('day', -30, CURRENT_DATE())
    GROUP BY 1
),
compute AS (
    SELECT DATE_TRUNC('day', START_TIME) AS D, SUM(CREDITS_USED) AS WH_CREDITS
    FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
    WHERE START_TIME >= DATEADD('day', -30, CURRENT_DATE())
    GROUP BY 1
)
SELECT
    COALESCE(t.D, c.D)                        AS USAGE_DAY,
    COALESCE(c.WH_CREDITS, 0)                 AS WAREHOUSE_CREDITS,
    COALESCE(t.TOKEN_CREDITS, 0)              AS TOKEN_CREDITS,
    COALESCE(c.WH_CREDITS, 0) + COALESCE(t.TOKEN_CREDITS, 0) AS TOTAL_CREDITS
FROM tokens t
FULL OUTER JOIN compute c ON c.D = t.D
ORDER BY USAGE_DAY DESC;

-- ---------------------------------------------------------------------------
-- 2. Token credits by function and model. Shows which call is the line item
--    and whether an expensive model is doing a cheap model's job.
-- ---------------------------------------------------------------------------

SELECT
    FUNCTION_NAME,
    MODEL_NAME,
    SUM(TOKENS)                                    AS TOKENS,
    SUM(TOKEN_CREDITS)                             AS TOKEN_CREDITS,
    RATIO_TO_REPORT(SUM(TOKEN_CREDITS)) OVER ()    AS SHARE_OF_TOKEN_SPEND
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_FUNCTIONS_USAGE_HISTORY
WHERE START_TIME >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY 1, 2
ORDER BY TOKEN_CREDITS DESC;

-- ---------------------------------------------------------------------------
-- 3. The most expensive individual AI queries.
--
--    CORTEX_FUNCTIONS_QUERY_USAGE_HISTORY carries no timestamp, so it must be
--    joined to QUERY_HISTORY to be filtered by date. This catches the query
--    that ran on more rows than anyone intended.
-- ---------------------------------------------------------------------------

SELECT
    q.QUERY_TAG,
    q.USER_NAME,
    q.WAREHOUSE_NAME,
    c.FUNCTION_NAME,
    c.MODEL_NAME,
    c.TOKENS,
    c.TOKEN_CREDITS,
    q.START_TIME,
    LEFT(q.QUERY_TEXT, 160) AS QUERY_PREVIEW
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_FUNCTIONS_QUERY_USAGE_HISTORY c
JOIN SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY q ON q.QUERY_ID = c.QUERY_ID
WHERE q.START_TIME >= DATEADD('day', -14, CURRENT_DATE())
ORDER BY c.TOKEN_CREDITS DESC
LIMIT 50;

-- ---------------------------------------------------------------------------
-- 4. AISQL spend attributed to a workload via QUERY_TAG.
--
--    QUERY_TAG is the only thing that makes spend attributable to a pipeline
--    rather than a person. Set it in every scheduled job:
--      ALTER SESSION SET QUERY_TAG = 'pipeline=text_scoring;env=prod';
-- ---------------------------------------------------------------------------

SELECT
    COALESCE(NULLIF(QUERY_TAG, ''), '(untagged)') AS WORKLOAD,
    FUNCTION_NAME,
    MODEL_NAME,
    COUNT(*)              AS CALLS,
    SUM(TOKENS)           AS TOKENS,
    SUM(TOKEN_CREDITS)    AS TOKEN_CREDITS
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
WHERE USAGE_TIME >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY 1, 2, 3
ORDER BY TOKEN_CREDITS DESC;

-- ---------------------------------------------------------------------------
-- 5. Cortex Search: indexing versus serving.
--
--    CONSUMPTION_TYPE separates the two. If indexing dominates, the refresh
--    lag is set tighter than the business needs.
-- ---------------------------------------------------------------------------

SELECT
    SERVICE_NAME,
    CONSUMPTION_TYPE,
    SUM(CREDITS) AS CREDITS,
    SUM(TOKENS)  AS TOKENS
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_SEARCH_DAILY_USAGE_HISTORY
WHERE USAGE_DATE >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY 1, 2
ORDER BY SERVICE_NAME, CREDITS DESC;

-- ---------------------------------------------------------------------------
-- 6. Agent and Analyst spend. Cost per question, by surface.
-- ---------------------------------------------------------------------------

SELECT
    AGENT_NAME,
    COUNT(DISTINCT REQUEST_ID)                          AS REQUESTS,
    SUM(TOKENS)                                         AS TOKENS,
    SUM(TOKEN_CREDITS)                                  AS TOKEN_CREDITS,
    DIV0(SUM(TOKEN_CREDITS), COUNT(DISTINCT REQUEST_ID)) AS CREDITS_PER_REQUEST
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AGENT_USAGE_HISTORY
WHERE START_TIME >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY 1
ORDER BY TOKEN_CREDITS DESC;

SELECT
    DATE_TRUNC('day', START_TIME)         AS USAGE_DAY,
    SUM(REQUEST_COUNT)                    AS ANALYST_REQUESTS,
    SUM(CREDITS)                          AS CREDITS,
    DIV0(SUM(CREDITS), SUM(REQUEST_COUNT)) AS CREDITS_PER_REQUEST
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_ANALYST_USAGE_HISTORY
WHERE START_TIME >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY 1
ORDER BY 1 DESC;

-- ---------------------------------------------------------------------------
-- 7. Warehouse credits attributed to a repeated query shape.
--
--    QUERY_PARAMETERIZED_HASH groups a query across its parameter values, so a
--    dashboard running the same aggregation for every viewer shows up as one
--    row with a high execution count. That is the materialization candidate.
-- ---------------------------------------------------------------------------

SELECT
    QUERY_PARAMETERIZED_HASH,
    COALESCE(NULLIF(QUERY_TAG, ''), '(untagged)') AS WORKLOAD,
    WAREHOUSE_NAME,
    COUNT(*)                                      AS EXECUTIONS,
    SUM(CREDITS_ATTRIBUTED_COMPUTE)               AS CREDITS,
    AVG(CREDITS_ATTRIBUTED_COMPUTE)               AS CREDITS_PER_EXECUTION
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY
WHERE START_TIME >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY 1, 2, 3
HAVING COUNT(*) > 20
ORDER BY CREDITS DESC
LIMIT 50;

-- ---------------------------------------------------------------------------
-- 8. Cost per answer, by workload. The metric to report.
--
--    A recurring workload whose cost per answer is not falling over time is a
--    workload that should have been pushed down a layer.
-- ---------------------------------------------------------------------------

WITH ai AS (
    SELECT
        COALESCE(NULLIF(QUERY_TAG, ''), '(untagged)') AS WORKLOAD,
        DATE_TRUNC('week', USAGE_TIME)                AS WK,
        COUNT(*)                                      AS CALLS,
        SUM(TOKEN_CREDITS)                            AS TOKEN_CREDITS
    FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
    WHERE USAGE_TIME >= DATEADD('day', -90, CURRENT_DATE())
    GROUP BY 1, 2
),
wh AS (
    SELECT
        COALESCE(NULLIF(QUERY_TAG, ''), '(untagged)') AS WORKLOAD,
        DATE_TRUNC('week', START_TIME)                AS WK,
        SUM(CREDITS_ATTRIBUTED_COMPUTE)               AS WH_CREDITS
    FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY
    WHERE START_TIME >= DATEADD('day', -90, CURRENT_DATE())
    GROUP BY 1, 2
)
SELECT
    COALESCE(a.WORKLOAD, w.WORKLOAD)                        AS WORKLOAD,
    COALESCE(a.WK, w.WK)                                    AS WEEK_START,
    COALESCE(a.CALLS, 0)                                    AS AI_CALLS,
    COALESCE(a.TOKEN_CREDITS, 0)                            AS TOKEN_CREDITS,
    COALESCE(w.WH_CREDITS, 0)                               AS WAREHOUSE_CREDITS,
    DIV0(COALESCE(a.TOKEN_CREDITS, 0) + COALESCE(w.WH_CREDITS, 0),
         NULLIF(COALESCE(a.CALLS, 0), 0))                   AS CREDITS_PER_CALL
FROM ai a
FULL OUTER JOIN wh w ON w.WORKLOAD = a.WORKLOAD AND w.WK = a.WK
ORDER BY WORKLOAD, WEEK_START DESC;
