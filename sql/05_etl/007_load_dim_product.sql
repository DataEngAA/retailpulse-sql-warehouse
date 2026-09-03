-- ============================================================
-- Load Product Dimension
--
-- For now Product is Type 1:
-- latest product attributes replace older values.
-- ============================================================


WITH latest_product AS (

    SELECT
        s.*,

        ROW_NUMBER() OVER (
            PARTITION BY s.product_id
            ORDER BY s.product_version_id DESC
        ) AS rn

    FROM staging.stg_products s

)

INSERT INTO warehouse.dim_product (

    product_id,
    product_name,
    category,
    brand,
    product_status,
    source_raw_record_id

)

SELECT

    product_id,
    product_name,
    category,
    brand,
    product_status,
    raw_record_id

FROM latest_product

WHERE rn = 1


ON CONFLICT (product_id)

DO UPDATE SET

    product_name =
        EXCLUDED.product_name,

    category =
        EXCLUDED.category,

    brand =
        EXCLUDED.brand,

    product_status =
        EXCLUDED.product_status,

    source_raw_record_id =
        EXCLUDED.source_raw_record_id,

    updated_at =
        clock_timestamp()

WHERE (

    warehouse.dim_product.product_name,
    warehouse.dim_product.category,
    warehouse.dim_product.brand,
    warehouse.dim_product.product_status

) IS DISTINCT FROM (

    EXCLUDED.product_name,
    EXCLUDED.category,
    EXCLUDED.brand,
    EXCLUDED.product_status

);