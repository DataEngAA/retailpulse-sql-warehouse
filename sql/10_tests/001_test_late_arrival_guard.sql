-- ============================================================
-- RetailPulse
-- Test: Late-arriving customer version must be rejected
--
-- This test uses TEMP data only.
-- It does NOT insert bad data into real staging.
-- ============================================================


BEGIN;


-- ============================================================
-- 1. Show baseline warehouse state
-- ============================================================

SELECT
    customer_id,
    city,
    valid_from,
    valid_to,
    is_current
FROM warehouse.dim_customer
WHERE customer_id = 200
  AND is_current = TRUE;


-- ============================================================
-- 2. Show baseline watermark
-- ============================================================

SELECT
    pipeline_name,
    last_processed_version_id
FROM control.pipeline_watermark
WHERE pipeline_name = 'dim_customer_incremental';


-- ============================================================
-- 3. Simulate a late-arriving incoming version
--
-- Current customer 200 starts at:
-- 2026-08-31 15:00
--
-- We simulate a record arriving with:
-- 2026-08-31 14:00
-- ============================================================

CREATE TEMP TABLE tmp_test_batch (
    customer_version_id BIGINT,
    customer_id BIGINT,
    city TEXT,
    effective_at TIMESTAMPTZ
)
ON COMMIT DROP;


INSERT INTO tmp_test_batch (
    customer_version_id,
    customer_id,
    city,
    effective_at
)
VALUES (
    999999,
    200,
    'Mumbai',
    '2026-08-31 14:00:00+05:30'
);


-- ============================================================
-- 4. Show why this version is late
-- ============================================================

SELECT
    b.customer_id,
    d.city AS warehouse_current_city,
    d.valid_from AS warehouse_valid_from,

    b.city AS incoming_city,
    b.effective_at AS incoming_effective_at,

    b.effective_at <= d.valid_from
        AS is_late_arrival

FROM tmp_test_batch b

JOIN warehouse.dim_customer d
    ON b.customer_id = d.customer_id
   AND d.is_current = TRUE;


-- ============================================================
-- 5. Create the same style of guard used by V2
-- ============================================================

CREATE TEMP TABLE tmp_late_arrival_guard (
    violation_count INTEGER NOT NULL,

    CONSTRAINT no_late_arriving_versions
        CHECK (violation_count = 0)
)
ON COMMIT DROP;


-- ============================================================
-- 6. This INSERT SHOULD FAIL
--
-- Expected:
-- violation_count = 1
-- CHECK constraint rejects it
-- transaction becomes aborted
-- ============================================================

INSERT INTO tmp_late_arrival_guard (
    violation_count
)

SELECT COUNT(*)

FROM tmp_test_batch b

JOIN warehouse.dim_customer d
    ON b.customer_id = d.customer_id
   AND d.is_current = TRUE

WHERE b.effective_at <= d.valid_from;


-- ============================================================
-- 7. End test and restore everything
-- ============================================================

ROLLBACK;