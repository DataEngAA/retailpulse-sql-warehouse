-- ============================================================
-- RetailPulse V3
-- Test routing of incoming staging versions
--
-- READ ONLY
-- No staging / warehouse / queue mutation.
-- ============================================================


WITH current_customer AS (

    SELECT
        customer_id,
        valid_from AS current_valid_from

    FROM warehouse.dim_customer

    WHERE customer_id = 101
      AND is_current = TRUE
),


synthetic_batch AS (

    -- Normal future version
    SELECT
        900001::BIGINT AS customer_version_id,
        c.customer_id,
        c.current_valid_from + INTERVAL '1 day'
            AS effective_at,
        'NORMAL_FUTURE_1'::TEXT AS test_case

    FROM current_customer c


    UNION ALL


    -- Historical / late-arriving version
    SELECT
        900002::BIGINT,
        c.customer_id,
        c.current_valid_from - INTERVAL '1 day',
        'LATE_HISTORICAL'

    FROM current_customer c


    UNION ALL


    -- Another normal future version
    SELECT
        900003::BIGINT,
        c.customer_id,
        c.current_valid_from + INTERVAL '2 days',
        'NORMAL_FUTURE_2'

    FROM current_customer c
),


classified AS (

    SELECT
        b.customer_version_id,
        b.customer_id,
        b.effective_at,
        b.test_case,

        d.valid_from AS warehouse_current_valid_from,

        CASE

            WHEN d.customer_sk IS NULL
                THEN 'NORMAL'

            WHEN b.effective_at <= d.valid_from
                THEN 'LATE'

            ELSE 'NORMAL'

        END AS route

    FROM synthetic_batch b

    LEFT JOIN warehouse.dim_customer d
        ON d.customer_id = b.customer_id
       AND d.is_current = TRUE
)


SELECT
    customer_version_id,
    customer_id,
    test_case,
    effective_at,
    warehouse_current_valid_from,
    route

FROM classified

ORDER BY customer_version_id;