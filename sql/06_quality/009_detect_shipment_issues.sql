-- ============================================================
-- RetailPulse
-- Detect RAW Shipment Quality Issues
-- ============================================================


-- 1. Missing shipment_id
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
    'shipments',
    s.raw_record_id,
    'shipment_id',
    'MISSING_SHIPMENT_ID',
    'ERROR',
    'REJECT',
    s.shipment_id

FROM raw.shipments s

WHERE s.shipment_id IS NULL
   OR BTRIM(s.shipment_id) = ''

ON CONFLICT (
    source_schema,
    source_table,
    raw_record_id,
    issue_code
)
DO NOTHING;



-- 2. Invalid shipment_id
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
    'shipments',
    s.raw_record_id,
    'shipment_id',
    'INVALID_SHIPMENT_ID',
    'ERROR',
    'REJECT',
    s.shipment_id

FROM raw.shipments s

WHERE s.shipment_id IS NOT NULL
  AND BTRIM(s.shipment_id) <> ''

  AND NOT pg_input_is_valid(
        BTRIM(s.shipment_id),
        'bigint'
      )

ON CONFLICT (
    source_schema,
    source_table,
    raw_record_id,
    issue_code
)
DO NOTHING;



-- 3. Missing / invalid order_id
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
    'shipments',
    s.raw_record_id,
    'order_id',

    CASE
        WHEN s.order_id IS NULL
          OR BTRIM(s.order_id) = ''
        THEN 'MISSING_ORDER_ID'
        ELSE 'INVALID_ORDER_ID'
    END,

    'ERROR',
    'REJECT',
    s.order_id

FROM raw.shipments s

WHERE s.order_id IS NULL
   OR BTRIM(s.order_id) = ''
   OR NOT pg_input_is_valid(
       BTRIM(s.order_id),
       'bigint'
   )

ON CONFLICT (
    source_schema,
    source_table,
    raw_record_id,
    issue_code
)
DO NOTHING;



-- 4. Invalid shipped_at
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
    'shipments',
    s.raw_record_id,
    'shipped_at',
    'INVALID_SHIPPED_AT',
    'ERROR',
    'REJECT',
    s.shipped_at

FROM raw.shipments s

WHERE s.shipped_at IS NULL
   OR BTRIM(s.shipped_at) = ''
   OR NOT pg_input_is_valid(
       BTRIM(s.shipped_at),
       'timestamptz'
   )

ON CONFLICT (
    source_schema,
    source_table,
    raw_record_id,
    issue_code
)
DO NOTHING;



-- 5. Invalid shipping_cost
--
-- Shipment is still useful.
-- Staging will convert the bad cost to NULL.
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
    'shipments',
    s.raw_record_id,
    'shipping_cost',
    'INVALID_SHIPPING_COST',
    'WARNING',
    'NULLIFY',
    s.shipping_cost

FROM raw.shipments s

WHERE s.shipping_cost IS NOT NULL
  AND BTRIM(s.shipping_cost) <> ''

  AND NOT pg_input_is_valid(
        BTRIM(s.shipping_cost),
        'numeric'
      )

ON CONFLICT (
    source_schema,
    source_table,
    raw_record_id,
    issue_code
)
DO NOTHING;



-- 6. Parent order not found yet
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
    'shipments',
    s.raw_record_id,
    'order_id',
    'ORDER_NOT_FOUND_YET',
    'WARNING',
    'FLAG',
    s.order_id

FROM raw.shipments s

WHERE s.order_id IS NOT NULL
  AND BTRIM(s.order_id) <> ''

  AND pg_input_is_valid(
      BTRIM(s.order_id),
      'bigint'
  )

  AND NOT EXISTS (

      SELECT 1
      FROM staging.stg_orders_current o

      WHERE o.order_id =
            BTRIM(s.order_id)::BIGINT
  )

ON CONFLICT (
    source_schema,
    source_table,
    raw_record_id,
    issue_code
)
DO NOTHING;



-- Show demo results
SELECT
    q.issue_id,
    q.raw_record_id,

    s.shipment_id,
    s.order_id,

    q.field_name,
    q.issue_code,

    q.severity,
    q.action,

    q.original_value

FROM audit.data_quality_issues q

JOIN raw.shipments s
    ON s.raw_record_id = q.raw_record_id

WHERE q.source_schema = 'raw'
  AND q.source_table = 'shipments'
  AND s.batch_id = 'shipment_demo_001'

ORDER BY
    q.raw_record_id,
    q.issue_id;