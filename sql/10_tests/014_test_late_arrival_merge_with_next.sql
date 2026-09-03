-- ============================================================
-- RetailPulse V3
-- Test MERGE_WITH_NEXT repair
--
-- Late state already equals the immediately next SCD2 state.
--
-- Mutates warehouse inside a transaction, verifies result,
-- then rolls back.
-- ============================================================


BEGIN;


-- ============================================================
-- 1. Capture containing + next interval
-- ============================================================

CREATE TEMP TABLE tmp_merge_context
ON COMMIT DROP
AS

SELECT
    c.customer_id,

    c.customer_sk AS containing_customer_sk,
    c.city AS containing_city,
    c.valid_from AS containing_valid_from,
    c.valid_to AS containing_valid_to,

    n.customer_sk AS next_customer_sk,
    n.city AS next_city,
    n.valid_from AS next_valid_from,
    n.valid_to AS next_valid_to,

    '2026-08-26 11:00:00+05:30'::TIMESTAMPTZ
        AS late_effective_at

FROM warehouse.dim_customer c

JOIN warehouse.dim_customer n
    ON n.customer_id = c.customer_id
   AND n.valid_from = c.valid_to

WHERE c.customer_id = 101

  AND tstzrange(
        c.valid_from,
        c.valid_to,
        '[)'
      )
      @>
      '2026-08-26 11:00:00+05:30'::TIMESTAMPTZ;



-- ============================================================
-- 2. Inspect context
-- ============================================================

SELECT *
FROM tmp_merge_context;



-- ============================================================
-- 3. FIRST shorten containing interval
--
-- Must happen first to avoid temporary overlap.
-- ============================================================

UPDATE warehouse.dim_customer d

SET
    valid_to = m.late_effective_at

FROM tmp_merge_context m

WHERE d.customer_sk =
      m.containing_customer_sk;



-- ============================================================
-- 4. THEN move existing next interval backward
--
-- Preserve next_customer_sk.
-- No new Mumbai row is inserted.
-- ============================================================

UPDATE warehouse.dim_customer d

SET
    valid_from = m.late_effective_at

FROM tmp_merge_context m

WHERE d.customer_sk =
      m.next_customer_sk;



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