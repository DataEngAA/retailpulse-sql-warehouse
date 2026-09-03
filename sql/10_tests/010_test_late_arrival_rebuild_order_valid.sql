-- ============================================================
-- RetailPulse V3 Exploration
-- Combine existing customer versions with one synthetic
-- late-arriving version and order everything by business time.
--
-- READ ONLY: does not modify staging or warehouse.
-- ============================================================


WITH incoming_version AS (

    SELECT
        101::BIGINT AS customer_id,

        '2026-08-26 11:00:00+05:30'::TIMESTAMPTZ
            AS effective_at,

        'Shimla'::TEXT AS incoming_city
),


matched_interval AS (

    SELECT
        d.customer_id,
        d.state,
        d.country,
        d.postal_code,
        d.customer_status,

        i.effective_at,
        i.incoming_city

    FROM incoming_version i

    JOIN warehouse.dim_customer d
        ON d.customer_id = i.customer_id

       AND tstzrange(
            d.valid_from,
            d.valid_to,
            '[)'
       ) @> i.effective_at
),


rebuild_source AS (

    -- Existing clean staging history
    SELECT
        s.customer_version_id,
        s.customer_id,

        s.city,
        s.state,
        s.country,
        s.postal_code,
        s.customer_status,

        s.effective_at,

        'STAGING'::TEXT AS record_source

    FROM staging.stg_customer_versions s

    WHERE s.customer_id = 101


    UNION ALL


    -- Synthetic late-arriving full SCD2 snapshot
    SELECT
        999999::BIGINT AS customer_version_id,

        m.customer_id,

        m.incoming_city AS city,
        m.state,
        m.country,
        m.postal_code,
        m.customer_status,

        m.effective_at,

        'SYNTHETIC_LATE'::TEXT AS record_source

    FROM matched_interval m
)


SELECT
    customer_version_id,
    customer_id,
    city,
    effective_at,
    record_source,

    ROW_NUMBER() OVER (
        PARTITION BY customer_id
        ORDER BY effective_at, customer_version_id
    ) AS history_seq

FROM rebuild_source

ORDER BY
    customer_id,
    effective_at,
    customer_version_id;