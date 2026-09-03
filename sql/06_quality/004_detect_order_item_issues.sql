-- ============================================================
-- RetailPulse
-- Detect RAW Order Item Quality Issues
--
-- Does NOT modify RAW.
-- Problems are recorded in:
-- audit.data_quality_issues
-- ============================================================


-- ============================================================
-- 1. Missing order_item_id
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
    'order_items',
    r.raw_record_id,
    'order_item_id',
    'MISSING_ORDER_ITEM_ID',
    'ERROR',
    'REJECT',
    r.order_item_id

FROM raw.order_items r

WHERE r.order_item_id IS NULL
   OR BTRIM(r.order_item_id) = ''

ON CONFLICT (
    source_schema,
    source_table,
    raw_record_id,
    issue_code
)
DO NOTHING;



-- ============================================================
-- 2. Invalid order_item_id
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
    'order_items',
    r.raw_record_id,
    'order_item_id',
    'INVALID_ORDER_ITEM_ID',
    'ERROR',
    'REJECT',
    r.order_item_id

FROM raw.order_items r

WHERE r.order_item_id IS NOT NULL
  AND BTRIM(r.order_item_id) <> ''

  AND NOT pg_input_is_valid(
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
    'order_items',
    r.raw_record_id,
    'order_id',

    CASE
        WHEN r.order_id IS NULL
          OR BTRIM(r.order_id) = ''
        THEN 'MISSING_ORDER_ID'

        ELSE 'INVALID_ORDER_ID'
    END,

    'ERROR',
    'REJECT',
    r.order_id

FROM raw.order_items r

WHERE r.order_id IS NULL
   OR BTRIM(r.order_id) = ''
   OR NOT pg_input_is_valid(
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
-- 4. Missing / invalid product_id
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
    'order_items',
    r.raw_record_id,
    'product_id',

    CASE
        WHEN r.product_id IS NULL
          OR BTRIM(r.product_id) = ''
        THEN 'MISSING_PRODUCT_ID'

        ELSE 'INVALID_PRODUCT_ID'
    END,

    'ERROR',
    'REJECT',
    r.product_id

FROM raw.order_items r

WHERE r.product_id IS NULL
   OR BTRIM(r.product_id) = ''
   OR NOT pg_input_is_valid(
       BTRIM(r.product_id),
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
-- 5. Invalid quantity
--
-- Quantity must:
--   be numeric
--   be greater than zero
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
    'order_items',
    r.raw_record_id,
    'quantity',
    'INVALID_QUANTITY',
    'ERROR',
    'REJECT',
    r.quantity

FROM raw.order_items r

WHERE

    r.quantity IS NULL

    OR BTRIM(r.quantity) = ''

    OR NOT pg_input_is_valid(
        BTRIM(r.quantity),
        'numeric'
    )

    OR CASE
        WHEN pg_input_is_valid(
            BTRIM(r.quantity),
            'numeric'
        )
        THEN BTRIM(r.quantity)::numeric <= 0
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
-- 6. Invalid unit_price
--
-- Price must be numeric and cannot be negative.
--
-- Zero is allowed because free/promotional items can exist.
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
    'order_items',
    r.raw_record_id,
    'unit_price',
    'INVALID_UNIT_PRICE',
    'ERROR',
    'REJECT',
    r.unit_price

FROM raw.order_items r

WHERE

    r.unit_price IS NULL

    OR BTRIM(r.unit_price) = ''

    OR NOT pg_input_is_valid(
        BTRIM(r.unit_price),
        'numeric'
    )

    OR CASE
        WHEN pg_input_is_valid(
            BTRIM(r.unit_price),
            'numeric'
        )
        THEN BTRIM(r.unit_price)::numeric < 0
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
-- 7. Parent order not found
--
-- Do NOT reject yet.
--
-- The order may simply arrive later.
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
    'order_items',
    i.raw_record_id,
    'order_id',
    'ORDER_NOT_FOUND_YET',
    'WARNING',
    'FLAG',
    i.order_id

FROM raw.order_items i

WHERE i.order_id IS NOT NULL
  AND BTRIM(i.order_id) <> ''

  AND NOT EXISTS (

      SELECT 1

      FROM raw.orders o

      WHERE BTRIM(o.order_id)
          = BTRIM(i.order_id)

  )

ON CONFLICT (
    source_schema,
    source_table,
    raw_record_id,
    issue_code
)
DO NOTHING;



-- ============================================================
-- Show results for our demo batch
-- ============================================================

SELECT

    q.issue_id,
    q.raw_record_id,

    i.order_item_id,
    i.order_id,

    q.field_name,
    q.issue_code,

    q.severity,
    q.action,

    q.original_value

FROM audit.data_quality_issues q

JOIN raw.order_items i

    ON i.raw_record_id =
       q.raw_record_id

WHERE q.source_schema = 'raw'

  AND q.source_table = 'order_items'

  AND i.batch_id =
      'sales_quality_demo_001'

ORDER BY
    q.raw_record_id,
    q.issue_id;