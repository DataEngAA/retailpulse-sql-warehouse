-- ============================================================
-- RetailPulse
-- Detect RAW Order Quality Issues
--
-- This script does NOT modify raw.orders.
--
-- It only records problems in:
-- audit.data_quality_issues
--
-- Idempotent:
-- rerunning it will not duplicate the same issue.
-- ============================================================


-- ============================================================
-- 1. Missing order_id
--
-- Without an order ID we cannot identify the order.
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
    'orders',
    r.raw_record_id,

    'order_id',
    'MISSING_ORDER_ID',

    'ERROR',
    'REJECT',

    r.order_id

FROM raw.orders r

WHERE r.order_id IS NULL
   OR BTRIM(r.order_id) = ''

ON CONFLICT (
    source_schema,
    source_table,
    raw_record_id,
    issue_code
)
DO NOTHING;



-- ============================================================
-- 2. Invalid order_id
--
-- For RetailPulse V1 we expect numeric order IDs.
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
    'orders',
    r.raw_record_id,

    'order_id',
    'INVALID_ORDER_ID',

    'ERROR',
    'REJECT',

    r.order_id

FROM raw.orders r

WHERE r.order_id IS NOT NULL

  AND BTRIM(r.order_id) <> ''

  AND NOT pg_input_is_valid(
        BTRIM(r.order_id),
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
-- 3. Missing / invalid customer_id
--
-- Orders must belong to a usable customer business ID.
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
    'orders',
    r.raw_record_id,

    'customer_id',

    CASE
        WHEN r.customer_id IS NULL
          OR BTRIM(r.customer_id) = ''
            THEN 'MISSING_CUSTOMER_ID'

        ELSE 'INVALID_CUSTOMER_ID'
    END,

    'ERROR',
    'REJECT',

    r.customer_id

FROM raw.orders r

WHERE

       r.customer_id IS NULL

    OR BTRIM(r.customer_id) = ''

    OR NOT pg_input_is_valid(
        BTRIM(r.customer_id),
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
-- 4. Invalid order_created_at
--
-- This is core business time.
-- If invalid, we cannot correctly place the sale in history.
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
    'orders',
    r.raw_record_id,

    'order_created_at',
    'INVALID_ORDER_CREATED_AT',

    'ERROR',
    'REJECT',

    r.order_created_at

FROM raw.orders r

WHERE

       r.order_created_at IS NULL

    OR BTRIM(r.order_created_at) = ''

    OR NOT pg_input_is_valid(
        BTRIM(r.order_created_at),
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
-- 5. Invalid shipping_amount
--
-- Bad shipping does NOT make the whole order unusable.
--
-- Keep order.
-- Staging will convert invalid shipping to NULL.
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
    'orders',
    r.raw_record_id,

    'shipping_amount',
    'INVALID_SHIPPING_AMOUNT',

    'WARNING',
    'NULLIFY',

    r.shipping_amount

FROM raw.orders r

WHERE r.shipping_amount IS NOT NULL

  AND BTRIM(r.shipping_amount) <> ''

  AND NOT pg_input_is_valid(
        BTRIM(r.shipping_amount),
        'numeric'
      )

ON CONFLICT (
    source_schema,
    source_table,
    raw_record_id,
    issue_code
)
DO NOTHING;



-- ============================================================
-- 6. Invalid order_discount_amount
--
-- Same principle as shipping.
-- Keep the order but do not invent a number.
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
    'orders',
    r.raw_record_id,

    'order_discount_amount',
    'INVALID_ORDER_DISCOUNT_AMOUNT',

    'WARNING',
    'NULLIFY',

    r.order_discount_amount

FROM raw.orders r

WHERE r.order_discount_amount IS NOT NULL

  AND BTRIM(r.order_discount_amount) <> ''

  AND NOT pg_input_is_valid(
        BTRIM(r.order_discount_amount),
        'numeric'
      )

ON CONFLICT (
    source_schema,
    source_table,
    raw_record_id,
    issue_code
)
DO NOTHING;



-- ============================================================
-- 7. Duplicate order_id
--
-- RAW keeps duplicates.
-- Quality layer flags them.
--
-- We are NOT deciding which version wins yet.
-- That decision belongs to staging/deduplication.
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
    'orders',
    r.raw_record_id,

    'order_id',
    'DUPLICATE_ORDER_ID',

    'WARNING',
    'FLAG',

    r.order_id

FROM raw.orders r

JOIN (

    SELECT
        BTRIM(order_id) AS order_id

    FROM raw.orders

    WHERE order_id IS NOT NULL
      AND BTRIM(order_id) <> ''

    GROUP BY BTRIM(order_id)

    HAVING COUNT(*) > 1

) duplicate_orders

    ON BTRIM(r.order_id) =
       duplicate_orders.order_id

ON CONFLICT (
    source_schema,
    source_table,
    raw_record_id,
    issue_code
)
DO NOTHING;



-- ============================================================
-- 8. Display detected issues for our demo batch
-- ============================================================

SELECT

    q.issue_id,
    q.raw_record_id,

    r.order_id,

    q.field_name,
    q.issue_code,

    q.severity,
    q.action,

    q.original_value

FROM audit.data_quality_issues q

JOIN raw.orders r

    ON r.raw_record_id =
       q.raw_record_id

WHERE q.source_schema = 'raw'

  AND q.source_table = 'orders'

  AND r.batch_id =
      'sales_quality_demo_001'

ORDER BY
    q.raw_record_id,
    q.issue_id;