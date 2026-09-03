-- ============================================================
-- RetailPulse
-- Load Order Item Fact
--
-- Grain:
-- one row = one order item
-- ============================================================


WITH latest_item AS (

    SELECT
        i.*,

        ROW_NUMBER() OVER (
            PARTITION BY i.order_item_id
            ORDER BY i.order_item_version_id DESC
        ) AS rn

    FROM staging.stg_order_items i

),

fact_source AS (

    SELECT

        i.order_item_id,

        o.order_id,

        c.customer_sk,

        p.product_sk,

        s.seller_sk,

        o.order_created_at,

        i.quantity,

        i.unit_price,

        COALESCE(i.discount_amount, 0) AS discount_amount,

        COALESCE(i.tax_amount, 0) AS tax_amount,

        o.currency,

        i.raw_record_id
            AS source_order_item_raw_record_id,

        o.raw_record_id
            AS source_order_raw_record_id

    FROM latest_item i

    JOIN staging.stg_orders_current o
        ON o.order_id = i.order_id


    -- Customer version valid when order happened
    JOIN warehouse.dim_customer c

        ON c.customer_id = o.customer_id

       AND tstzrange(
            c.valid_from,
            c.valid_to,
            '[)'
       ) @> o.order_created_at


    JOIN warehouse.dim_product p
        ON p.product_id = i.product_id


    LEFT JOIN warehouse.dim_seller s
        ON s.seller_id = i.seller_id


    WHERE i.rn = 1

)

INSERT INTO warehouse.fact_order_item (

    order_item_id,
    order_id,

    customer_sk,
    product_sk,
    seller_sk,

    order_created_at,

    quantity,
    unit_price,
    discount_amount,
    tax_amount,

    gross_amount,
    net_amount,

    currency,

    source_order_item_raw_record_id,
    source_order_raw_record_id

)

SELECT

    order_item_id,
    order_id,

    customer_sk,
    product_sk,
    seller_sk,

    order_created_at,

    quantity,
    unit_price,
    discount_amount,
    tax_amount,

    ROUND(
        quantity * unit_price,
        2
    ) AS gross_amount,

    ROUND(
        (quantity * unit_price)
        - discount_amount
        + tax_amount,
        2
    ) AS net_amount,

    currency,

    source_order_item_raw_record_id,
    source_order_raw_record_id

FROM fact_source


ON CONFLICT (order_item_id)

DO UPDATE SET

    order_id =
        EXCLUDED.order_id,

    customer_sk =
        EXCLUDED.customer_sk,

    product_sk =
        EXCLUDED.product_sk,

    seller_sk =
        EXCLUDED.seller_sk,

    order_created_at =
        EXCLUDED.order_created_at,

    quantity =
        EXCLUDED.quantity,

    unit_price =
        EXCLUDED.unit_price,

    discount_amount =
        EXCLUDED.discount_amount,

    tax_amount =
        EXCLUDED.tax_amount,

    gross_amount =
        EXCLUDED.gross_amount,

    net_amount =
        EXCLUDED.net_amount,

    currency =
        EXCLUDED.currency,

    source_order_item_raw_record_id =
        EXCLUDED.source_order_item_raw_record_id,

    source_order_raw_record_id =
        EXCLUDED.source_order_raw_record_id

WHERE (

    warehouse.fact_order_item.order_id,
    warehouse.fact_order_item.customer_sk,
    warehouse.fact_order_item.product_sk,
    warehouse.fact_order_item.seller_sk,
    warehouse.fact_order_item.order_created_at,
    warehouse.fact_order_item.quantity,
    warehouse.fact_order_item.unit_price,
    warehouse.fact_order_item.discount_amount,
    warehouse.fact_order_item.tax_amount,
    warehouse.fact_order_item.currency

) IS DISTINCT FROM (

    EXCLUDED.order_id,
    EXCLUDED.customer_sk,
    EXCLUDED.product_sk,
    EXCLUDED.seller_sk,
    EXCLUDED.order_created_at,
    EXCLUDED.quantity,
    EXCLUDED.unit_price,
    EXCLUDED.discount_amount,
    EXCLUDED.tax_amount,
    EXCLUDED.currency

);