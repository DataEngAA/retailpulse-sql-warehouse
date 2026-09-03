-- ============================================================
-- RetailPulse
-- Detect RAW Payment Quality Issues
-- ============================================================


-- ============================================================
-- 1. Missing payment_id
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
    'payments',
    p.raw_record_id,
    'payment_id',
    'MISSING_PAYMENT_ID',
    'ERROR',
    'REJECT',
    p.payment_id

FROM raw.payments p

WHERE p.payment_id IS NULL
   OR BTRIM(p.payment_id) = ''

ON CONFLICT (
    source_schema,
    source_table,
    raw_record_id,
    issue_code
)
DO NOTHING;



-- ============================================================
-- 2. Invalid payment_id
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
    'payments',
    p.raw_record_id,
    'payment_id',
    'INVALID_PAYMENT_ID',
    'ERROR',
    'REJECT',
    p.payment_id

FROM raw.payments p

WHERE p.payment_id IS NOT NULL

  AND BTRIM(p.payment_id) <> ''

  AND NOT pg_input_is_valid(
        BTRIM(p.payment_id),
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
-- 3. Missing / invalid order_id
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
    'payments',
    p.raw_record_id,
    'order_id',

    CASE
        WHEN p.order_id IS NULL
          OR BTRIM(p.order_id) = ''
        THEN 'MISSING_ORDER_ID'

        ELSE 'INVALID_ORDER_ID'
    END,

    'ERROR',
    'REJECT',
    p.order_id

FROM raw.payments p

WHERE p.order_id IS NULL
   OR BTRIM(p.order_id) = ''
   OR NOT pg_input_is_valid(
       BTRIM(p.order_id),
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
-- 4. Invalid payment amount
--
-- Amount must be numeric and >= 0.
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
    'payments',
    p.raw_record_id,
    'payment_amount',
    'INVALID_PAYMENT_AMOUNT',
    'ERROR',
    'REJECT',
    p.payment_amount

FROM raw.payments p

WHERE

       p.payment_amount IS NULL

    OR BTRIM(p.payment_amount) = ''

    OR NOT pg_input_is_valid(
        BTRIM(p.payment_amount),
        'numeric'
    )

    OR CASE
        WHEN pg_input_is_valid(
            BTRIM(p.payment_amount),
            'numeric'
        )
        THEN BTRIM(p.payment_amount)::numeric < 0
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
-- 5. Invalid payment timestamp
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
    'payments',
    p.raw_record_id,
    'payment_created_at',
    'INVALID_PAYMENT_CREATED_AT',
    'ERROR',
    'REJECT',
    p.payment_created_at

FROM raw.payments p

WHERE p.payment_created_at IS NULL

   OR BTRIM(p.payment_created_at) = ''

   OR NOT pg_input_is_valid(
       BTRIM(p.payment_created_at),
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
-- 6. Parent order not found yet
--
-- Do not reject.
-- The order may arrive later.
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
    'payments',
    p.raw_record_id,
    'order_id',
    'ORDER_NOT_FOUND_YET',
    'WARNING',
    'FLAG',
    p.order_id

FROM raw.payments p

WHERE p.order_id IS NOT NULL

  AND BTRIM(p.order_id) <> ''

  AND pg_input_is_valid(
      BTRIM(p.order_id),
      'bigint'
  )

  AND NOT EXISTS (

      SELECT 1

      FROM staging.stg_orders_current o

      WHERE o.order_id =
            BTRIM(p.order_id)::BIGINT

  )

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

    p.payment_id,
    p.order_id,

    q.field_name,
    q.issue_code,

    q.severity,
    q.action,

    q.original_value

FROM audit.data_quality_issues q

JOIN raw.payments p
    ON p.raw_record_id = q.raw_record_id

WHERE q.source_schema = 'raw'
  AND q.source_table = 'payments'
  AND p.batch_id = 'payment_demo_001'

ORDER BY
    q.raw_record_id,
    q.issue_id;