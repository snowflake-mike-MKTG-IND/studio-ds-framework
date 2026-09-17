-- Read-only fixtures. No model calls and no database objects required.
-- The hash expression and match predicates are checked against production SQL by node tests.
WITH fixture AS (
    SELECT column1::VARCHAR AS CASE_NAME, column2::NUMBER AS TITLE_ID,
           column3::VARCHAR AS AUTHOR_HASH, column4::VARCHAR AS ITEM_TEXT
    FROM VALUES
        ('base', 1, 'author-a', 'I will attend this film'),
        ('duplicate', 1, 'author-a', 'I will attend this film'),
        ('null_author', 1, NULL, 'I will attend this film'),
        ('empty_author', 1, '', 'I will attend this film'),
        ('changed_text', 1, 'author-a', 'I will not attend this film'),
        ('pipe_left', 1, 'author|part', 'text with a separator'),
        ('pipe_right', 1, 'author', 'part|text with a separator'),
        ('null_title', NULL, 'author-a', 'I will attend this film')
), keyed AS (
    SELECT *, SHA2(TO_JSON(ARRAY_CONSTRUCT(TITLE_ID, AUTHOR_HASH, ITEM_TEXT)), 256) AS ITEM_HASH
    FROM fixture
), expected AS (
    SELECT column1::VARCHAR AS CASE_NAME, column2::VARCHAR AS SCORER_VERSION,
           column3::NUMBER AS EXPECTED_PENDING
    FROM VALUES ('base', 'v1', 0), ('duplicate', 'v1', 0), ('null_author', 'v1', 0),
                ('changed_text', 'v1', 1), ('base', 'v2', 1), ('null_title', 'v1', 0)
), stored AS (
    SELECT ITEM_HASH, 'v1' AS SCORER_VERSION,
           IFF(CASE_NAME = 'null_author', 'REVIEW_REQUIRED', 'SUCCEEDED') AS SCORE_STATUS
    FROM keyed WHERE CASE_NAME IN ('base', 'null_author')
), actual AS (
    SELECT expected.*,
           IFF(keyed.TITLE_ID IS NOT NULL AND NOT EXISTS (
               SELECT 1 FROM stored result
               WHERE result.ITEM_HASH = keyed.ITEM_HASH
                 AND result.SCORER_VERSION = expected.SCORER_VERSION
           ), 1, 0) AS ACTUAL_PENDING
    FROM expected JOIN keyed ON keyed.CASE_NAME = expected.CASE_NAME
), cases AS (
    SELECT CASE_NAME || '_' || SCORER_VERSION AS TEST_NAME,
           ACTUAL_PENDING = EXPECTED_PENDING AS PASSED FROM actual
    UNION ALL
    SELECT 'null_author_hash_is_not_null', ITEM_HASH IS NOT NULL FROM keyed WHERE CASE_NAME = 'null_author'
    UNION ALL
    SELECT 'null_and_empty_author_differ', COUNT(DISTINCT ITEM_HASH) = 2
    FROM keyed WHERE CASE_NAME IN ('null_author', 'empty_author')
    UNION ALL
    SELECT 'delimiter_collision_prevented', COUNT(DISTINCT ITEM_HASH) = 2
    FROM keyed WHERE CASE_NAME IN ('pipe_left', 'pipe_right')
    UNION ALL
    SELECT 'duplicate_tuple_same_key', COUNT(DISTINCT ITEM_HASH) = 1
    FROM keyed WHERE CASE_NAME IN ('base', 'duplicate')
    UNION ALL
    SELECT 'prompt_change_changes_version',
        SHA2(TO_JSON(ARRAY_CONSTRUCT('v2', 'managed', ['yes','no'], 'original', 'single')), 256)
        <> SHA2(TO_JSON(ARRAY_CONSTRUCT('v2', 'managed', ['yes','no'], 'revised', 'single')), 256)
    UNION ALL
    SELECT 'model_policy_change_changes_version',
        SHA2(TO_JSON(ARRAY_CONSTRUCT('v2', 'model-a', ['yes','no'], 'task', 'single')), 256)
        <> SHA2(TO_JSON(ARRAY_CONSTRUCT('v2', 'model-b', ['yes','no'], 'task', 'single')), 256)
)
SELECT TEST_NAME, IFF(COALESCE(PASSED, FALSE), 'PASS', 'FAIL') AS RESULT
FROM cases ORDER BY TEST_NAME;