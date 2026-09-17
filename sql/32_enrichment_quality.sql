-- Read-only. Duplicate/invalid gold keys invalidate the evaluation.
-- Missing or failed predictions count as errors, never silently disappear.

SELECT 'duplicate_result_key' AS FINDING, ITEM_HASH, SCORER_VERSION, COUNT(*) AS ROWS_AT_GRAIN
FROM STUDIO_DS.CURATED.TEXT_ENRICHMENT_RESULT
GROUP BY ITEM_HASH, SCORER_VERSION
HAVING COUNT(*) > 1;

SELECT 'invalid_gold_key_or_label' AS FINDING, ITEM_HASH, COUNT(*) AS ROWS_AT_GRAIN
FROM STUDIO_DS.OPS.INTENT_GOLD
GROUP BY ITEM_HASH
HAVING COUNT(*) > 1 OR ITEM_HASH IS NULL
    OR COUNT_IF(TRUE_INTENT IS NULL OR TRUE_INTENT NOT IN
        ('WILL_ATTEND', 'INTERESTED', 'WILL_NOT_ATTEND', 'OFF_TOPIC')) > 0;

WITH classes AS (
    SELECT VALUE::VARCHAR AS CLASS_NAME
    FROM TABLE(FLATTEN(INPUT => ['WILL_ATTEND', 'INTERESTED', 'WILL_NOT_ATTEND', 'OFF_TOPIC']))
), evaluated AS (
    SELECT gold.ITEM_HASH, gold.TRUE_INTENT,
           IFF(result.SCORE_STATUS = 'SUCCEEDED', result.INTENT, NULL) AS PRED_INTENT
    FROM STUDIO_DS.OPS.INTENT_GOLD gold
    CROSS JOIN STUDIO_DS.CURATED.TEXT_SCORING_CONFIG config
    LEFT JOIN STUDIO_DS.CURATED.TEXT_ENRICHMENT_RESULT result
        ON result.ITEM_HASH = gold.ITEM_HASH AND result.SCORER_VERSION = config.SCORER_VERSION
), counts AS (
    SELECT classes.CLASS_NAME,
        COUNT(evaluated.ITEM_HASH) AS GOLD_ITEMS,
        COUNT(evaluated.PRED_INTENT) AS PREDICTED_ITEMS,
        COUNT(CASE WHEN evaluated.TRUE_INTENT = classes.CLASS_NAME THEN 1 END) AS CLASS_SUPPORT,
        COUNT(CASE WHEN evaluated.PRED_INTENT = classes.CLASS_NAME
                 AND evaluated.TRUE_INTENT = classes.CLASS_NAME THEN 1 END) AS TP,
        COUNT(CASE WHEN evaluated.PRED_INTENT = classes.CLASS_NAME
                 AND evaluated.TRUE_INTENT <> classes.CLASS_NAME THEN 1 END) AS FP,
        COUNT(CASE WHEN evaluated.TRUE_INTENT = classes.CLASS_NAME
                 AND (evaluated.PRED_INTENT <> classes.CLASS_NAME OR evaluated.PRED_INTENT IS NULL) THEN 1 END) AS FN
    FROM classes LEFT JOIN evaluated ON TRUE
    GROUP BY classes.CLASS_NAME
), scores AS (
    SELECT *,
        PREDICTED_ITEMS / NULLIF(GOLD_ITEMS, 0) AS PREDICTION_COVERAGE,
        TP / NULLIF(TP + FP, 0) AS PRECISION,
        TP / NULLIF(TP + FN, 0) AS RECALL,
        2 * TP / NULLIF(2 * TP + FP + FN, 0) AS F1
    FROM counts
)
SELECT *,
    IFF(MIN(CLASS_SUPPORT) OVER () > 0, AVG(F1) OVER (), NULL) AS MACRO_F1,
    CASE WHEN GOLD_ITEMS = 0 THEN 'STOP: empty gold set'
         WHEN MIN(CLASS_SUPPORT) OVER () = 0 THEN 'STOP: missing class support'
         WHEN PREDICTED_ITEMS <> GOLD_ITEMS THEN 'STOP: incomplete predictions'
         ELSE 'REVIEW: compare quality with the predeclared threshold' END AS EVALUATION_STATUS
FROM scores
ORDER BY CLASS_NAME;