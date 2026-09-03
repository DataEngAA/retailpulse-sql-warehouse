-- ============================================================
-- RetailPulse
-- Detect RAW Seller Quality Issues
-- ============================================================


-- ============================================================
-- 1. Missing seller_id
-- ============================================================

INSERT INTO audit.data_quality_issues (
    source_schema,
    source_table,
    raw_record_id,
    field_name,
    issue_code,
    severity,
    action,
    original_value
)

SELECT
    'raw',
    'sellers',
    s.raw_record_id,
    'seller_id',
    'MISSING_SELLER_ID',
    'ERROR',
    'REJECT',
    s.seller_id

FROM raw.sellers s

WHERE s.seller_id IS NULL
   OR BTRIM(s.seller_id) = ''

ON CONFLICT (
    source_schema,
    source_table,
    raw_record_id,
    issue_code
)
DO NOTHING;



-- ============================================================
-- 2. Invalid seller_id
-- ============================================================

INSERT INTO audit.data_quality_issues (
    source_schema,
    source_table,
    raw_record_id,
    field_name,
    issue_code,
    severity,
    action,
    original_value
)

SELECT
    'raw',
    'sellers',
    s.raw_record_id,
    'seller_id',
    'INVALID_SELLER_ID',
    'ERROR',
    'REJECT',
    s.seller_id

FROM raw.sellers s

WHERE s.seller_id IS NOT NULL

  AND BTRIM(s.seller_id) <> ''

  AND NOT pg_input_is_valid(
        BTRIM(s.seller_id),
        'bigint'
      )

ON CONFLICT (
    source_schema,
    source_table,
    raw_record_id,
    issue_code
)
DO NOTHING;



-- ============================================================
-- 3. Missing seller_name
-- ============================================================

INSERT INTO audit.data_quality_issues (
    source_schema,
    source_table,
    raw_record_id,
    field_name,
    issue_code,
    severity,
    action,
    original_value
)

SELECT
    'raw',
    'sellers',
    s.raw_record_id,
    'seller_name',
    'MISSING_SELLER_NAME',
    'ERROR',
    'REJECT',
    s.seller_name

FROM raw.sellers s

WHERE s.seller_name IS NULL
   OR BTRIM(s.seller_name) = ''

ON CONFLICT (
    source_schema,
    source_table,
    raw_record_id,
    issue_code
)
DO NOTHING;



-- ============================================================
-- Show demo results
-- ============================================================

SELECT
    q.issue_id,
    q.raw_record_id,
    s.seller_id,
    s.seller_name,
    q.field_name,
    q.issue_code,
    q.severity,
    q.action

FROM audit.data_quality_issues q

JOIN raw.sellers s
    ON s.raw_record_id = q.raw_record_id

WHERE q.source_schema = 'raw'
  AND q.source_table = 'sellers'
  AND s.batch_id = 'seller_demo_001'

ORDER BY
    q.raw_record_id,
    q.issue_id;