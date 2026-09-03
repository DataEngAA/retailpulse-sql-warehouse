-- ============================================================
-- RetailPulse V3
-- Test targeted late-arrival interval repair
--
-- This test mutates the real warehouse INSIDE a transaction,
-- verifies the result, then rolls everything back.
-- ============================================================


BEGIN;


-- ============================================================
-- 1. Capture the affected existing interval
-- ============================================================

CREATE TEMP TABLE tmp_target_interval
ON COMMIT DROP
AS

SELECT
    d.*,

    '2026-08-26 11:00:00+05:30'::TIMESTAMPTZ
        AS late_effective_at,

    'Shimla'::TEXT
        AS late_city

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
-- 2. Inspect what we are about to split
-- ============================================================

SELECT
    customer_sk,
    customer_id,
    city,
    valid_from,
    valid_to,
    late_effective_at,
    late_city

FROM tmp_target_interval;



-- ============================================================
-- 3. Shorten the existing Delhi interval
--
-- Preserve the existing customer_sk.
-- ============================================================

UPDATE warehouse.dim_customer d

SET
    valid_to = t.late_effective_at

FROM tmp_target_interval t

WHERE d.customer_sk = t.customer_sk;



-- ============================================================
-- 4. Insert the late-arriving state
--
-- It receives a new surrogate key.
-- Its valid_to is the ORIGINAL Delhi valid_to.
-- ============================================================

INSERT INTO warehouse.dim_customer (

    customer_id,

    first_name,
    last_name,
    email,
    phone,
    date_of_birth,
    signup_date,

    city,
    state,
    country,
    postal_code,
    customer_status,

    valid_from,
    valid_to,
    is_current,

    source_raw_record_id

)

SELECT

    customer_id,

    first_name,
    last_name,
    email,
    phone,
    date_of_birth,
    signup_date,

    late_city,
    state,
    country,
    postal_code,
    customer_status,

    late_effective_at,
    valid_to,
    FALSE,

    999999

FROM tmp_target_interval;



-- ============================================================
-- 5. Verify repaired history
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
-- 6. Roll back test
-- ============================================================

ROLLBACK;