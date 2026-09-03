WITH latest_return AS (

    SELECT
        r.*,

        ROW_NUMBER() OVER (
            PARTITION BY r.return_id
            ORDER BY r.return_version_id DESC
        ) AS rn

    FROM staging.stg_returns r
),

fact_source AS (

    SELECT

        r.return_id,

        f.order_item_id,
        f.order_id,

        f.customer_sk,
        f.product_sk,
        f.seller_sk,

        r.return_status,

        r.return_quantity,

        r.refund_amount,

        r.return_reason,

        r.requested_at,

        r.completed_at,

        r.raw_record_id
            AS source_return_raw_record_id

    FROM latest_return r

    JOIN warehouse.fact_order_item f
        ON f.order_item_id = r.order_item_id

    WHERE r.rn = 1
)

INSERT INTO warehouse.fact_return (

    return_id,

    order_item_id,
    order_id,

    customer_sk,
    product_sk,
    seller_sk,

    return_status,

    return_quantity,
    refund_amount,

    return_reason,

    requested_at,
    completed_at,

    source_return_raw_record_id

)

SELECT

    return_id,

    order_item_id,
    order_id,

    customer_sk,
    product_sk,
    seller_sk,

    return_status,

    return_quantity,
    refund_amount,

    return_reason,

    requested_at,
    completed_at,

    source_return_raw_record_id

FROM fact_source

ON CONFLICT (return_id)

DO UPDATE SET

    order_item_id =
        EXCLUDED.order_item_id,

    order_id =
        EXCLUDED.order_id,

    customer_sk =
        EXCLUDED.customer_sk,

    product_sk =
        EXCLUDED.product_sk,

    seller_sk =
        EXCLUDED.seller_sk,

    return_status =
        EXCLUDED.return_status,

    return_quantity =
        EXCLUDED.return_quantity,

    refund_amount =
        EXCLUDED.refund_amount,

    return_reason =
        EXCLUDED.return_reason,

    requested_at =
        EXCLUDED.requested_at,

    completed_at =
        EXCLUDED.completed_at,

    source_return_raw_record_id =
        EXCLUDED.source_return_raw_record_id

WHERE (

    warehouse.fact_return.order_item_id,
    warehouse.fact_return.return_status,
    warehouse.fact_return.return_quantity,
    warehouse.fact_return.refund_amount,
    warehouse.fact_return.return_reason,
    warehouse.fact_return.requested_at,
    warehouse.fact_return.completed_at

) IS DISTINCT FROM (

    EXCLUDED.order_item_id,
    EXCLUDED.return_status,
    EXCLUDED.return_quantity,
    EXCLUDED.refund_amount,
    EXCLUDED.return_reason,
    EXCLUDED.requested_at,
    EXCLUDED.completed_at

);