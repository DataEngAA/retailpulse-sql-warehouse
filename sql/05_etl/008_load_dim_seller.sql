WITH latest_seller AS (

    SELECT
        s.*,

        ROW_NUMBER() OVER (
            PARTITION BY s.seller_id
            ORDER BY s.seller_version_id DESC
        ) AS rn

    FROM staging.stg_sellers s

)

INSERT INTO warehouse.dim_seller (

    seller_id,
    seller_name,
    seller_status,
    country,
    source_raw_record_id

)

SELECT

    seller_id,
    seller_name,
    seller_status,
    country,
    raw_record_id

FROM latest_seller

WHERE rn = 1


ON CONFLICT (seller_id)

DO UPDATE SET

    seller_name =
        EXCLUDED.seller_name,

    seller_status =
        EXCLUDED.seller_status,

    country =
        EXCLUDED.country,

    source_raw_record_id =
        EXCLUDED.source_raw_record_id,

    updated_at =
        clock_timestamp()

WHERE (

    warehouse.dim_seller.seller_name,
    warehouse.dim_seller.seller_status,
    warehouse.dim_seller.country

) IS DISTINCT FROM (

    EXCLUDED.seller_name,
    EXCLUDED.seller_status,
    EXCLUDED.country

);