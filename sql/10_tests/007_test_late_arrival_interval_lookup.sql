-- ============================================================
-- RetailPulse V3 Exploration
-- Find the warehouse interval containing a late-arriving event
-- ============================================================


WITH incoming_version AS (

    SELECT
        101::BIGINT AS customer_id,

        '2026-08-26 10:00:00+05:30'::TIMESTAMPTZ
            AS effective_at,

        'Shimla'::TEXT AS incoming_city
)

SELECT
    i.customer_id,

    i.effective_at AS incoming_effective_at,
    i.incoming_city,

    d.customer_sk,

    d.city AS existing_city,

    d.valid_from,
    d.valid_to,

    tstzrange(
        d.valid_from,
        d.valid_to,
        '[)'
    ) AS existing_validity_range

FROM incoming_version i

JOIN warehouse.dim_customer d
    ON d.customer_id = i.customer_id

   AND tstzrange(
        d.valid_from,
        d.valid_to,
        '[)'
   ) @> i.effective_at;