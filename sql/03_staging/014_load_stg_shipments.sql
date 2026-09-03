-- ============================================================
-- Load trusted Shipments into STAGING
--
-- Safe casts are used for all RAW values.
-- ============================================================


WITH prepared_shipments AS (

    SELECT
        s.*,


        -- shipment_id
        CASE
            WHEN s.shipment_id IS NOT NULL
             AND BTRIM(s.shipment_id) <> ''
             AND pg_input_is_valid(
                    BTRIM(s.shipment_id),
                    'bigint'
                 )
            THEN BTRIM(s.shipment_id)::BIGINT

            ELSE NULL
        END AS shipment_id_typed,


        -- order_id
        CASE
            WHEN s.order_id IS NOT NULL
             AND BTRIM(s.order_id) <> ''
             AND pg_input_is_valid(
                    BTRIM(s.order_id),
                    'bigint'
                 )
            THEN BTRIM(s.order_id)::BIGINT

            ELSE NULL
        END AS order_id_typed,


        -- shipped_at
        CASE
            WHEN s.shipped_at IS NOT NULL
             AND BTRIM(s.shipped_at) <> ''
             AND pg_input_is_valid(
                    BTRIM(s.shipped_at),
                    'timestamptz'
                 )
            THEN BTRIM(s.shipped_at)::TIMESTAMPTZ

            ELSE NULL
        END AS shipped_at_typed,


        -- delivered_at is optional
        CASE
            WHEN s.delivered_at IS NOT NULL
             AND BTRIM(s.delivered_at) <> ''
             AND pg_input_is_valid(
                    BTRIM(s.delivered_at),
                    'timestamptz'
                 )
            THEN BTRIM(s.delivered_at)::TIMESTAMPTZ

            ELSE NULL
        END AS delivered_at_typed,


        -- bad shipping cost becomes NULL
        CASE
            WHEN s.shipping_cost IS NOT NULL
             AND BTRIM(s.shipping_cost) <> ''
             AND pg_input_is_valid(
                    BTRIM(s.shipping_cost),
                    'numeric'
                 )
            THEN BTRIM(s.shipping_cost)::NUMERIC(18,2)

            ELSE NULL
        END AS shipping_cost_typed


    FROM raw.shipments s
)


INSERT INTO staging.stg_shipments (

    raw_record_id,

    shipment_id,
    order_id,

    carrier,
    tracking_number,
    shipment_status,

    shipped_at,
    delivered_at,

    shipping_cost,

    source_system,
    batch_id,
    ingested_at

)

SELECT

    s.raw_record_id,

    s.shipment_id_typed,
    s.order_id_typed,

    NULLIF(BTRIM(s.carrier), ''),

    NULLIF(BTRIM(s.tracking_number), ''),

    UPPER(NULLIF(BTRIM(s.shipment_status), '')),

    s.shipped_at_typed,

    s.delivered_at_typed,

    s.shipping_cost_typed,

    s.source_system,
    s.batch_id,
    s.ingested_at

FROM prepared_shipments s


-- No rejected rows
WHERE NOT EXISTS (

    SELECT 1

    FROM audit.data_quality_issues q

    WHERE q.source_schema = 'raw'
      AND q.source_table = 'shipments'
      AND q.raw_record_id = s.raw_record_id
      AND q.action = 'REJECT'

)


-- Required values must still be valid
AND s.shipment_id_typed IS NOT NULL

AND s.order_id_typed IS NOT NULL

AND s.shipped_at_typed IS NOT NULL


-- Parent order must exist
AND EXISTS (

    SELECT 1

    FROM staging.stg_orders_current o

    WHERE o.order_id =
          s.order_id_typed

)


-- Do not load same RAW record twice
AND NOT EXISTS (

    SELECT 1

    FROM staging.stg_shipments st

    WHERE st.raw_record_id =
          s.raw_record_id

);