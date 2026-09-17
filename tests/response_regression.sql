-- Read-only response parsing fixtures. No model calls or database objects.
WITH fixture AS (
    SELECT column1::VARCHAR AS TEST_NAME, PARSE_JSON(column2) AS SENTIMENT_RESPONSE,
           PARSE_JSON(column3) AS INTENT_RESPONSE, column4::VARCHAR AS EXPECTED_STATUS
    FROM VALUES
        ('json_null_errors',
         '{"value":{"categories":[{"name":"overall","sentiment":"positive"}]},"error":null}',
         '{"value":{"labels":["WILL_ATTEND"]},"error":null}', 'SUCCEEDED'),
        ('absent_errors',
         '{"value":{"categories":[{"name":"overall","sentiment":"mixed"}]}}',
         '{"value":{"labels":["INTERESTED"]}}', 'SUCCEEDED'),
        ('failed_intent',
         '{"value":{"categories":[{"name":"overall","sentiment":"positive"}]},"error":null}',
         '{"value":null,"error":"temporary failure"}', 'REVIEW_REQUIRED'),
        ('null_response', NULL, NULL, 'REVIEW_REQUIRED'),
        ('invalid_label',
         '{"value":{"categories":[{"name":"overall","sentiment":"positive"}]},"error":null}',
         '{"value":{"labels":["MAYBE"]},"error":null}', 'REVIEW_REQUIRED'),
        ('valid_value_with_error',
         '{"value":{"categories":[{"name":"overall","sentiment":"positive"}]},"error":"failed"}',
         '{"value":{"labels":["WILL_ATTEND"]},"error":null}', 'REVIEW_REQUIRED')
), parsed AS (
    SELECT *,
        SENTIMENT_RESPONSE:value:categories[0]:sentiment::VARCHAR AS SENTIMENT,
        INTENT_RESPONSE:value:labels[0]::VARCHAR AS INTENT,
        CASE WHEN SENTIMENT IN ('positive', 'negative', 'neutral', 'mixed', 'unknown')
                  AND INTENT IN ('WILL_ATTEND', 'INTERESTED', 'WILL_NOT_ATTEND', 'OFF_TOPIC')
                  AND (SENTIMENT_RESPONSE:error IS NULL OR IS_NULL_VALUE(SENTIMENT_RESPONSE:error))
                  AND (INTENT_RESPONSE:error IS NULL OR IS_NULL_VALUE(INTENT_RESPONSE:error))
             THEN 'SUCCEEDED' ELSE 'REVIEW_REQUIRED' END AS SCORE_STATUS
    FROM fixture
)
SELECT TEST_NAME, IFF(SCORE_STATUS = EXPECTED_STATUS, 'PASS', 'FAIL') AS RESULT
FROM parsed ORDER BY TEST_NAME;