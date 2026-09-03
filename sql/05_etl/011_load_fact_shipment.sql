-- ============================================================
-- RetailPulse
-- Load Shipment Fact
--
-- Grain:
-- one row = one shipment
--
-- Later versions update the existing shipment row.
-- ============================================================


WITH latest_shipment AS (

    SELECT

        s.*,

        ROW_NUMBER() OVER (
            PARTITION BY s.shipment_id
            ORDER BY s.shipment_version_id DESC
        ) AS rn

    FROM staging.stg_shipments s

),

fact_source AS (

    SELECT

        s.shipment_id,

        s.order_id,

        c.customer_sk,

        s.carrier,

        s.tracking_number,

        s.shipment_status,

        s.shipped_at,

        s.delivered_at,

        s.shipping_cost,

        s.raw_record_id
            AS source_shipment_raw_record_id,

        o.raw_record_id
            AS source_order_raw_record_id

    FROM latest_shipment s

    JOIN staging.stg_orders_current o
        ON o.order_id = s.order_id


    -- Customer version valid when shipment occurred
    JOIN warehouse.dim_customer c

        ON c.customer_id = o.customer_id

       AND tstzrange(
            c.valid_from,
            c.valid_to,
            '[)'
       ) @> s.shipped_at


    WHERE s.rn = 1

)

INSERT INTO warehouse.fact_shipment (

    shipment_id,

    order_id,

    customer_sk,

    carrier,

    tracking_number,

    shipment_status,

    shipped_at,

    delivered_at,

    shipping_cost,

    source_shipment_raw_record_id,

    source_order_raw_record_id

)

SELECT

    shipment_id,

    order_id,

    customer_sk,

    carrier,

    tracking_number,

    shipment_status,

    shipped_at,

    delivered_at,

    shipping_cost,

    source_shipment_raw_record_id,

    source_order_raw_record_id

FROM fact_source


ON CONFLICT (shipment_id)

DO UPDATE SET

    order_id =
        EXCLUDED.order_id,

    customer_sk =
        EXCLUDED.customer_sk,

    carrier =
        EXCLUDED.carrier,

    tracking_number =
        EXCLUDED.tracking_number,

    shipment_status =
        EXCLUDED.shipment_status,

    shipped_at =
        EXCLUDED.shipped_at,

    delivered_at =
        EXCLUDED.delivered_at,

    shipping_cost =
        EXCLUDED.shipping_cost,

    source_shipment_raw_record_id =
        EXCLUDED.source_shipment_raw_record_id,

    source_order_raw_record_id =
        EXCLUDED.source_order_raw_record_id

WHERE (

    warehouse.fact_shipment.order_id,
    warehouse.fact_shipment.customer_sk,
    warehouse.fact_shipment.carrier,
    warehouse.fact_shipment.tracking_number,
    warehouse.fact_shipment.shipment_status,
    warehouse.fact_shipment.shipped_at,
    warehouse.fact_shipment.delivered_at,
    warehouse.fact_shipment.shipping_cost

) IS DISTINCT FROM (

    EXCLUDED.order_id,
    EXCLUDED.customer_sk,
    EXCLUDED.carrier,
    EXCLUDED.tracking_number,
    EXCLUDED.shipment_status,
    EXCLUDED.shipped_at,
    EXCLUDED.delivered_at,
    EXCLUDED.shipping_cost

);