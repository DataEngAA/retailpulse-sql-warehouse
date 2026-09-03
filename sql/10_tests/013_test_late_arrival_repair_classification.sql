-- ============================================================
-- RetailPulse V3
-- Classify the mutation required for a late-arriving SCD2 row
--
-- READ ONLY
-- ============================================================


WITH parameters AS (

    SELECT
        101::BIGINT AS customer_id,

        '2026-08-26 11:00:00+05:30'::TIMESTAMPTZ
            AS late_effective_at
),


-- ============================================================
-- Find the interval containing the late timestamp
-- ============================================================

containing_interval AS (

    SELECT
        d.*

    FROM warehouse.dim_customer d

    JOIN parameters p
        ON p.customer_id = d.customer_id

    WHERE tstzrange(
            d.valid_from,
            d.valid_to,
            '[)'
          )
          @> p.late_effective_at
),


-- ============================================================
-- Find the immediately adjacent next interval
--
-- For a normal continuous SCD2 timeline:
-- current.valid_to = next.valid_from
-- ============================================================

history_context AS (

    SELECT
        c.*,

        n.customer_sk AS next_customer_sk,

        n.city AS next_city,
        n.state AS next_state,
        n.country AS next_country,
        n.postal_code AS next_postal_code,
        n.customer_status AS next_customer_status

    FROM containing_interval c

    LEFT JOIN warehouse.dim_customer n
        ON n.customer_id = c.customer_id
       AND n.valid_from = c.valid_to
),


-- ============================================================
-- Build three synthetic scenarios
-- ============================================================

test_cases AS (

    -- --------------------------------------------------------
    -- Case 1:
    -- incoming state is identical to containing interval
    -- --------------------------------------------------------

    SELECT
        'CASE_1_SAME_AS_CURRENT'::TEXT AS scenario,

        p.late_effective_at,

        h.customer_id,

        h.city,
        h.state,
        h.country,
        h.postal_code,
        h.customer_status

    FROM history_context h
    CROSS JOIN parameters p


    UNION ALL


    -- --------------------------------------------------------
    -- Case 2:
    -- genuinely new SCD2 state
    -- --------------------------------------------------------

    SELECT
        'CASE_2_NEW_STATE'::TEXT,

        p.late_effective_at,

        h.customer_id,

        'Shimla'::TEXT,
        h.state,
        h.country,
        h.postal_code,
        h.customer_status

    FROM history_context h
    CROSS JOIN parameters p


    UNION ALL


    -- --------------------------------------------------------
    -- Case 3:
    -- incoming state already equals the NEXT interval
    -- --------------------------------------------------------

    SELECT
        'CASE_3_SAME_AS_NEXT'::TEXT,

        p.late_effective_at,

        h.customer_id,

        h.next_city,
        h.next_state,
        h.next_country,
        h.next_postal_code,
        h.next_customer_status

    FROM history_context h
    CROSS JOIN parameters p

    WHERE h.next_customer_sk IS NOT NULL
),


classified AS (

    SELECT
        t.scenario,

        t.customer_id,
        t.late_effective_at,

        t.city AS incoming_city,

        h.customer_sk AS containing_customer_sk,
        h.city AS containing_city,

        h.next_customer_sk,
        h.next_city,

        CASE

            -- Incoming state already matches containing state
            WHEN ROW(
                t.city,
                t.state,
                t.country,
                t.postal_code,
                t.customer_status
            )
            IS NOT DISTINCT FROM
            ROW(
                h.city,
                h.state,
                h.country,
                h.postal_code,
                h.customer_status
            )

            THEN 'NO_SCD2_CHANGE'


            -- Incoming state matches immediately next state
            WHEN h.next_customer_sk IS NOT NULL

             AND ROW(
                    t.city,
                    t.state,
                    t.country,
                    t.postal_code,
                    t.customer_status
                 )
                 IS NOT DISTINCT FROM
                 ROW(
                    h.next_city,
                    h.next_state,
                    h.next_country,
                    h.next_postal_code,
                    h.next_customer_status
                 )

            THEN 'MERGE_WITH_NEXT'


            -- New state between both existing states
            ELSE 'SPLIT_INSERT'

        END AS repair_action

    FROM test_cases t

    JOIN history_context h
        ON h.customer_id = t.customer_id
)


SELECT
    scenario,
    incoming_city,

    containing_customer_sk,
    containing_city,

    next_customer_sk,
    next_city,

    repair_action

FROM classified

ORDER BY scenario;