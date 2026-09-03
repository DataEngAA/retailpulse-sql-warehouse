WITH latest_payment AS (

    SELECT
        p.*,

        ROW_NUMBER() OVER (
            PARTITION BY p.payment_id
            ORDER BY p.payment_version_id DESC
        ) AS rn

    FROM staging.stg_payments p

),

fact_source AS (

    SELECT

        p.payment_id,

        p.order_id,

        c.customer_sk,

        p.payment_type,
        p.payment_status,
        p.payment_method,

        p.payment_amount,
        p.currency,

        p.payment_created_at,

        p.transaction_reference,

        p.raw_record_id
            AS source_payment_raw_record_id,

        o.raw_record_id
            AS source_order_raw_record_id

    FROM latest_payment p

    JOIN staging.stg_orders_current o
        ON o.order_id = p.order_id

    -- Customer version valid when payment happened
    JOIN warehouse.dim_customer c
        ON c.customer_id = o.customer_id

       AND tstzrange(
            c.valid_from,
            c.valid_to,
            '[)'
       ) @> p.payment_created_at

    WHERE p.rn = 1
)

INSERT INTO warehouse.fact_payment (

    payment_id,
    order_id,
    customer_sk,

    payment_type,
    payment_status,
    payment_method,

    payment_amount,
    currency,

    payment_created_at,

    transaction_reference,

    source_payment_raw_record_id,
    source_order_raw_record_id

)

SELECT

    payment_id,
    order_id,
    customer_sk,

    payment_type,
    payment_status,
    payment_method,

    payment_amount,
    currency,

    payment_created_at,

    transaction_reference,

    source_payment_raw_record_id,
    source_order_raw_record_id

FROM fact_source

ON CONFLICT (payment_id)

DO UPDATE SET

    order_id =
        EXCLUDED.order_id,

    customer_sk =
        EXCLUDED.customer_sk,

    payment_type =
        EXCLUDED.payment_type,

    payment_status =
        EXCLUDED.payment_status,

    payment_method =
        EXCLUDED.payment_method,

    payment_amount =
        EXCLUDED.payment_amount,

    currency =
        EXCLUDED.currency,

    payment_created_at =
        EXCLUDED.payment_created_at,

    transaction_reference =
        EXCLUDED.transaction_reference,

    source_payment_raw_record_id =
        EXCLUDED.source_payment_raw_record_id,

    source_order_raw_record_id =
        EXCLUDED.source_order_raw_record_id

WHERE (

    warehouse.fact_payment.order_id,
    warehouse.fact_payment.customer_sk,
    warehouse.fact_payment.payment_type,
    warehouse.fact_payment.payment_status,
    warehouse.fact_payment.payment_method,
    warehouse.fact_payment.payment_amount,
    warehouse.fact_payment.currency,
    warehouse.fact_payment.payment_created_at,
    warehouse.fact_payment.transaction_reference

) IS DISTINCT FROM (

    EXCLUDED.order_id,
    EXCLUDED.customer_sk,
    EXCLUDED.payment_type,
    EXCLUDED.payment_status,
    EXCLUDED.payment_method,
    EXCLUDED.payment_amount,
    EXCLUDED.currency,
    EXCLUDED.payment_created_at,
    EXCLUDED.transaction_reference

);