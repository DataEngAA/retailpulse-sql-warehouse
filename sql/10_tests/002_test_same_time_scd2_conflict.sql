-- ============================================================
-- RetailPulse
-- Test: conflicting SCD2 states at the same effective timestamp
-- must be rejected.
--
-- Uses TEMP data only.
-- ============================================================


BEGIN;


-- ============================================================
-- 1. Baseline warehouse state
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
-- 2. Baseline watermark
-- ============================================================

SELECT
    pipeline_name,
    last_processed_version_id
FROM control.pipeline_watermark
WHERE pipeline_name = 'dim_customer_incremental';


-- ============================================================
-- 3. Simulate two conflicting SCD2 states
--    at exactly the same business timestamp
-- ============================================================

CREATE TEMP TABLE tmp_test_batch (
    customer_version_id BIGINT,
    customer_id BIGINT,
    effective_at TIMESTAMPTZ,

    city TEXT,
    state TEXT,
    country TEXT,
    postal_code TEXT,
    customer_status TEXT
)
ON COMMIT DROP;


INSERT INTO tmp_test_batch (
    customer_version_id,
    customer_id,
    effective_at,
    city,
    customer_status
)
VALUES
(
    999001,
    200,
    '2026-09-01 10:00:00+05:30',
    'Delhi',
    'active'
),
(
    999002,
    200,
    '2026-09-01 10:00:00+05:30',
    'Mumbai',
    'active'
);


-- ============================================================
-- 4. Show the ambiguous timestamp
-- ============================================================

SELECT
    customer_id,
    effective_at,
    COUNT(*) AS versions_at_same_time,
    COUNT(
        DISTINCT ROW(
            city,
            state,
            country,
            postal_code,
            customer_status
        )
    ) AS distinct_scd2_states

FROM tmp_test_batch

GROUP BY
    customer_id,
    effective_at;


-- ============================================================
-- 5. Create the same-time safety guard
-- ============================================================

CREATE TEMP TABLE tmp_same_time_guard (
    violation_count INTEGER NOT NULL,

    CONSTRAINT no_ambiguous_same_time_scd2_versions
        CHECK (violation_count = 0)
)
ON COMMIT DROP;


-- ============================================================
-- 6. This INSERT SHOULD FAIL
-- ============================================================

INSERT INTO tmp_same_time_guard (
    violation_count
)

SELECT COUNT(*)

FROM (
    SELECT
        customer_id,
        effective_at

    FROM (
        SELECT DISTINCT
            customer_id,
            effective_at,
            city,
            state,
            country,
            postal_code,
            customer_status

        FROM tmp_test_batch
    ) distinct_states

    GROUP BY
        customer_id,
        effective_at

    HAVING COUNT(*) > 1

) conflicts;


-- ============================================================
-- 7. Restore everything
-- ============================================================

ROLLBACK;