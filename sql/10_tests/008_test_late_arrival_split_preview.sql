-- ============================================================
-- RetailPulse V3 Exploration
-- Preview how a historical interval would be split
-- without changing warehouse data.
-- ============================================================


WITH incoming_version AS (

    SELECT
        101::BIGINT AS customer_id,

        '2026-08-26 10:00:00+05:30'::TIMESTAMPTZ
            AS effective_at,

        'Shimla'::TEXT AS incoming_city
),


matched_interval AS (

    SELECT
        i.customer_id,
        i.effective_at AS incoming_effective_at,
        i.incoming_city,

        d.customer_sk,
        d.city AS existing_city,

        d.valid_from,
        d.valid_to

    FROM incoming_version i

    JOIN warehouse.dim_customer d
        ON d.customer_id = i.customer_id

       AND tstzrange(
            d.valid_from,
            d.valid_to,
            '[)'
       ) @> i.effective_at
),


proposed_history AS (

    -- Existing state before late-arriving change
    SELECT
        customer_id,
        existing_city AS city,

        valid_from,
        incoming_effective_at AS valid_to,

        'EXISTING_LEFT_SIDE'::TEXT AS segment_type

    FROM matched_interval


    UNION ALL


    -- Late-arriving state
    SELECT
        customer_id,
        incoming_city AS city,

        incoming_effective_at AS valid_from,
        valid_to,

        'LATE_ARRIVING_STATE'::TEXT AS segment_type

    FROM matched_interval
)


SELECT
    customer_id,
    city,
    valid_from,
    valid_to,
    segment_type

FROM proposed_history

ORDER BY valid_from;