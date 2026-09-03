-- ============================================================
-- RetailPulse V3 Exploration
-- Rebuild corrected SCD2 history after inserting a valid
-- synthetic late-arriving version.
--
-- READ ONLY: warehouse is not modified.
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

    -- Existing cleaned staging history
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


    -- Synthetic late-arriving SCD2 state
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
),


ordered_history AS (

    SELECT
        r.*,

        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY effective_at, customer_version_id
        ) AS history_seq,

        LAG(city) OVER (
            PARTITION BY customer_id
            ORDER BY effective_at, customer_version_id
        ) AS prev_city,

        LAG(state) OVER (
            PARTITION BY customer_id
            ORDER BY effective_at, customer_version_id
        ) AS prev_state,

        LAG(country) OVER (
            PARTITION BY customer_id
            ORDER BY effective_at, customer_version_id
        ) AS prev_country,

        LAG(postal_code) OVER (
            PARTITION BY customer_id
            ORDER BY effective_at, customer_version_id
        ) AS prev_postal_code,

        LAG(customer_status) OVER (
            PARTITION BY customer_id
            ORDER BY effective_at, customer_version_id
        ) AS prev_customer_status

    FROM rebuild_source r
),


real_scd2_changes AS (

    SELECT *

    FROM ordered_history

    WHERE
        history_seq = 1

        OR city IS DISTINCT FROM prev_city
        OR state IS DISTINCT FROM prev_state
        OR country IS DISTINCT FROM prev_country
        OR postal_code IS DISTINCT FROM prev_postal_code
        OR customer_status IS DISTINCT FROM prev_customer_status
),


rebuilt_history AS (

    SELECT
        customer_version_id,
        customer_id,
        city,
        effective_at AS valid_from,

        LEAD(effective_at) OVER (
            PARTITION BY customer_id
            ORDER BY effective_at, customer_version_id
        ) AS valid_to,

        record_source

    FROM real_scd2_changes
)


SELECT
    customer_version_id,
    customer_id,
    city,
    valid_from,
    valid_to,

    valid_to IS NULL AS is_current,

    record_source

FROM rebuilt_history

ORDER BY valid_from;