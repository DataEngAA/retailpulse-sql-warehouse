-- ============================================================
-- RetailPulse
-- Detect RAW Product Quality Issues
-- ============================================================


-- ============================================================
-- 1. Missing product_id
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
    'products',
    p.raw_record_id,
    'product_id',
    'MISSING_PRODUCT_ID',
    'ERROR',
    'REJECT',
    p.product_id

FROM raw.products p

WHERE p.product_id IS NULL
   OR BTRIM(p.product_id) = ''

ON CONFLICT (
    source_schema,
    source_table,
    raw_record_id,
    issue_code
)
DO NOTHING;



-- ============================================================
-- 2. Invalid product_id
--
-- RetailPulse V1 expects numeric product IDs.
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
    'products',
    p.raw_record_id,
    'product_id',
    'INVALID_PRODUCT_ID',
    'ERROR',
    'REJECT',
    p.product_id

FROM raw.products p

WHERE p.product_id IS NOT NULL

  AND BTRIM(p.product_id) <> ''

  AND NOT pg_input_is_valid(
        BTRIM(p.product_id),
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
-- 3. Missing product_name
--
-- An ID alone is not enough for a useful product dimension.
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
    'products',
    p.raw_record_id,
    'product_name',
    'MISSING_PRODUCT_NAME',
    'ERROR',
    'REJECT',
    p.product_name

FROM raw.products p

WHERE p.product_name IS NULL
   OR BTRIM(p.product_name) = ''

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
    p.product_id,
    p.product_name,
    q.field_name,
    q.issue_code,
    q.severity,
    q.action

FROM audit.data_quality_issues q

JOIN raw.products p
    ON p.raw_record_id = q.raw_record_id

WHERE q.source_schema = 'raw'
  AND q.source_table = 'products'
  AND p.batch_id = 'product_demo_001'

ORDER BY
    q.raw_record_id,
    q.issue_id;