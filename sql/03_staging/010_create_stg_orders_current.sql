CREATE OR REPLACE VIEW staging.stg_orders_current AS

WITH ranked_orders AS (

    SELECT
        s.*,

        ROW_NUMBER() OVER (
            PARTITION BY s.order_id

            ORDER BY
                s.order_updated_at DESC NULLS LAST,
                s.order_created_at DESC,
                s.order_version_id DESC
        ) AS rn

    FROM staging.stg_orders s

)

SELECT
    order_version_id,
    raw_record_id,
    order_id,
    customer_id,
    order_status,
    order_created_at,
    order_updated_at,
    currency,
    shipping_amount,
    order_discount_amount,
    source_system,
    batch_id,
    ingested_at

FROM ranked_orders

WHERE rn = 1;