-- ============================================================
-- RetailPulse
-- Detect RAW Return Quality Issues
-- ============================================================


-- ============================================================
-- 1. Missing return_id
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
    'returns',
    r.raw_record_id,
    'return_id',
    'MISSING_RETURN_ID',
    'ERROR',
    'REJECT',
    r.return_id

FROM raw.returns r

WHERE r.return_id IS NULL
   OR BTRIM(r.return_id) = ''

ON CONFLICT (
    source_schema,
    source_table,
    raw_record_id,
    issue_code
)
DO NOTHING;



-- ============================================================
-- 2. Invalid return_id
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
    'returns',
    r.raw_record_id,
    'return_id',
    'INVALID_RETURN_ID',
    'ERROR',
    'REJECT',
    r.return_id

FROM raw.returns r

WHERE r.return_id IS NOT NULL
  AND BTRIM(r.return_id) <> ''

  AND NOT pg_input_is_valid(
        BTRIM(r.return_id),
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
-- 3. Missing / invalid order_item_id
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
    'returns',
    r.raw_record_id,
    'order_item_id',

    CASE
        WHEN r.order_item_id IS NULL
          OR BTRIM(r.order_item_id) = ''
        THEN 'MISSING_ORDER_ITEM_ID'

        ELSE 'INVALID_ORDER_ITEM_ID'
    END,

    'ERROR',
    'REJECT',
    r.order_item_id

FROM raw.returns r

WHERE r.order_item_id IS NULL
   OR BTRIM(r.order_item_id) = ''

   OR NOT pg_input_is_valid(
        BTRIM(r.order_item_id),
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
-- 4. Invalid return quantity
--
-- Must be numeric and greater than zero.
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
    'returns',
    r.raw_record_id,
    'return_quantity',
    'INVALID_RETURN_QUANTITY',
    'ERROR',
    'REJECT',
    r.return_quantity

FROM raw.returns r

WHERE

       r.return_quantity IS NULL

    OR BTRIM(r.return_quantity) = ''

    OR NOT pg_input_is_valid(
        BTRIM(r.return_quantity),
        'numeric'
    )

    OR CASE
        WHEN pg_input_is_valid(
            BTRIM(r.return_quantity),
            'numeric'
        )
        THEN BTRIM(r.return_quantity)::NUMERIC <= 0

        ELSE FALSE
    END

ON CONFLICT (
    source_schema,
    source_table,
    raw_record_id,
    issue_code
)
DO NOTHING;



-- ============================================================
-- 5. Invalid refund amount
--
-- Refund must be numeric and cannot be negative.
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
    'returns',
    r.raw_record_id,
    'refund_amount',
    'INVALID_REFUND_AMOUNT',
    'ERROR',
    'REJECT',
    r.refund_amount

FROM raw.returns r

WHERE

       r.refund_amount IS NULL

    OR BTRIM(r.refund_amount) = ''

    OR NOT pg_input_is_valid(
        BTRIM(r.refund_amount),
        'numeric'
    )

    OR CASE
        WHEN pg_input_is_valid(
            BTRIM(r.refund_amount),
            'numeric'
        )
        THEN BTRIM(r.refund_amount)::NUMERIC < 0

        ELSE FALSE
    END

ON CONFLICT (
    source_schema,
    source_table,
    raw_record_id,
    issue_code
)
DO NOTHING;



-- ============================================================
-- 6. Invalid requested_at
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
    'returns',
    r.raw_record_id,
    'requested_at',
    'INVALID_RETURN_REQUESTED_AT',
    'ERROR',
    'REJECT',
    r.requested_at

FROM raw.returns r

WHERE r.requested_at IS NULL
   OR BTRIM(r.requested_at) = ''

   OR NOT pg_input_is_valid(
        BTRIM(r.requested_at),
        'timestamptz'
      )

ON CONFLICT (
    source_schema,
    source_table,
    raw_record_id,
    issue_code
)
DO NOTHING;



-- ============================================================
-- 7. Invalid completed_at
--
-- completed_at is optional.
-- But if supplied, it must be a valid timestamp.
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
    'returns',
    r.raw_record_id,
    'completed_at',
    'INVALID_RETURN_COMPLETED_AT',
    'ERROR',
    'REJECT',
    r.completed_at

FROM raw.returns r

WHERE r.completed_at IS NOT NULL
  AND BTRIM(r.completed_at) <> ''

  AND NOT pg_input_is_valid(
        BTRIM(r.completed_at),
        'timestamptz'
      )

ON CONFLICT (
    source_schema,
    source_table,
    raw_record_id,
    issue_code
)
DO NOTHING;



-- ============================================================
-- 8. Order item not found yet
--
-- Do NOT permanently reject it.
-- Maybe the sales item arrives later.
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
    'returns',
    r.raw_record_id,
    'order_item_id',
    'ORDER_ITEM_NOT_FOUND_YET',
    'WARNING',
    'FLAG',
    r.order_item_id

FROM raw.returns r

WHERE r.order_item_id IS NOT NULL

  AND BTRIM(r.order_item_id) <> ''

  AND pg_input_is_valid(
        BTRIM(r.order_item_id),
        'bigint'
      )

  AND NOT EXISTS (

      SELECT 1

      FROM warehouse.fact_order_item f

      WHERE f.order_item_id =
            BTRIM(r.order_item_id)::BIGINT
  )

ON CONFLICT (
    source_schema,
    source_table,
    raw_record_id,
    issue_code
)
DO NOTHING;



-- ============================================================
-- 9. Return quantity greater than quantity sold
--
-- This is our new cross-table business rule.
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
    'returns',
    r.raw_record_id,
    'return_quantity',
    'RETURN_QUANTITY_EXCEEDS_SOLD',
    'ERROR',
    'REJECT',
    r.return_quantity

FROM raw.returns r

JOIN warehouse.fact_order_item f

    ON pg_input_is_valid(
        BTRIM(r.order_item_id),
        'bigint'
    )

   AND f.order_item_id =
       BTRIM(r.order_item_id)::BIGINT

WHERE pg_input_is_valid(
        BTRIM(r.return_quantity),
        'numeric'
      )

  AND BTRIM(r.return_quantity)::NUMERIC
      > f.quantity

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

    r.return_id,
    r.order_item_id,

    q.field_name,
    q.issue_code,

    q.severity,
    q.action,

    q.original_value

FROM audit.data_quality_issues q

JOIN raw.returns r
    ON r.raw_record_id = q.raw_record_id

WHERE q.source_schema = 'raw'
  AND q.source_table = 'returns'
  AND r.batch_id = 'return_demo_001'

ORDER BY
    q.raw_record_id,
    q.issue_id;