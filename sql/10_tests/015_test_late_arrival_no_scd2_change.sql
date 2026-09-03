-- ============================================================
-- RetailPulse V3
-- Test NO_SCD2_CHANGE repair path
--
-- Incoming late state is identical to the containing
-- historical SCD2 state.
--
-- READ/verification only.
-- ============================================================


BEGIN;


-- ============================================================
-- 1. Capture warehouse state before test
-- ============================================================

CREATE TEMP TABLE tmp_before_history
ON COMMIT DROP
AS

SELECT
    customer_sk,
    customer_id,
    city,
    state,
    country,
    postal_code,
    customer_status,
    valid_from,
    valid_to,
    is_current

FROM warehouse.dim_customer

WHERE customer_id = 101;



-- ============================================================
-- 2. Find containing interval
-- ============================================================

CREATE TEMP TABLE tmp_no_change_context
ON COMMIT DROP
AS

SELECT
    d.*,

    '2026-08-26 11:00:00+05:30'::TIMESTAMPTZ
        AS late_effective_at,

    -- Incoming state deliberately equals existing Delhi state
    d.city AS incoming_city,
    d.state AS incoming_state,
    d.country AS incoming_country,
    d.postal_code AS incoming_postal_code,
    d.customer_status AS incoming_customer_status

FROM warehouse.dim_customer d

WHERE d.customer_id = 101

  AND tstzrange(
        d.valid_from,
        d.valid_to,
        '[)'
      )
      @>
      '2026-08-26 11:00:00+05:30'::TIMESTAMPTZ;



-- ============================================================
-- 3. Classify
-- ============================================================

SELECT
    customer_sk,
    city AS containing_city,
    incoming_city,

    CASE

        WHEN ROW(
            incoming_city,
            incoming_state,
            incoming_country,
            incoming_postal_code,
            incoming_customer_status
        )
        IS NOT DISTINCT FROM
        ROW(
            city,
            state,
            country,
            postal_code,
            customer_status
        )

        THEN 'NO_SCD2_CHANGE'

        ELSE 'UNEXPECTED_CHANGE'

    END AS repair_action

FROM tmp_no_change_context;



-- ============================================================
-- 4. Verify no warehouse mutation occurred
-- ============================================================

SELECT
    customer_sk,
    customer_id,
    city,
    valid_from,
    valid_to,
    is_current

FROM warehouse.dim_customer

WHERE customer_id = 101

ORDER BY valid_from;



-- ============================================================
-- 5. Prove before and after history are identical
-- ============================================================

SELECT COUNT(*) AS changed_rows
FROM (

    (
        SELECT *
        FROM tmp_before_history

        EXCEPT

        SELECT
            customer_sk,
            customer_id,
            city,
            state,
            country,
            postal_code,
            customer_status,
            valid_from,
            valid_to,
            is_current

        FROM warehouse.dim_customer

        WHERE customer_id = 101
    )

    UNION ALL

    (
        SELECT
            customer_sk,
            customer_id,
            city,
            state,
            country,
            postal_code,
            customer_status,
            valid_from,
            valid_to,
            is_current

        FROM warehouse.dim_customer

        WHERE customer_id = 101

        EXCEPT

        SELECT *
        FROM tmp_before_history
    )

) differences;



ROLLBACK;