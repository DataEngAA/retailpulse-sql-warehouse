-- ============================================================
-- RetailPulse V3
-- Test normal/late handoff + queue idempotency
--
-- Real queue is used inside a transaction.
-- Everything is rolled back at the end.
-- ============================================================


BEGIN;


-- ============================================================
-- 1. Build synthetic mixed batch
-- ============================================================

CREATE TEMP TABLE tmp_test_routing_batch
ON COMMIT DROP
AS

WITH current_customer AS (

    SELECT
        customer_id,
        valid_from AS current_valid_from

    FROM warehouse.dim_customer

    WHERE customer_id = 101
      AND is_current = TRUE
)

SELECT
    910001::BIGINT AS customer_version_id,
    c.customer_id,
    c.current_valid_from + INTERVAL '1 day'
        AS effective_at,
    'NORMAL_FUTURE_1'::TEXT AS test_case

FROM current_customer c


UNION ALL


SELECT
    910002::BIGINT,
    c.customer_id,
    c.current_valid_from - INTERVAL '1 day',
    'LATE_HISTORICAL'

FROM current_customer c


UNION ALL


SELECT
    910003::BIGINT,
    c.customer_id,
    c.current_valid_from + INTERVAL '2 days',
    'NORMAL_FUTURE_2'

FROM current_customer c;



-- ============================================================
-- 2. Classify NORMAL vs LATE
-- ============================================================

CREATE TEMP TABLE tmp_test_routed
ON COMMIT DROP
AS

SELECT
    b.*,

    CASE

        WHEN d.customer_sk IS NULL
            THEN 'NORMAL'

        WHEN b.effective_at <= d.valid_from
            THEN 'LATE'

        ELSE 'NORMAL'

    END AS route

FROM tmp_test_routing_batch b

LEFT JOIN warehouse.dim_customer d
    ON d.customer_id = b.customer_id
   AND d.is_current = TRUE;



-- ============================================================
-- 3. NORMAL rows remain available for normal V2 processing
-- ============================================================

CREATE TEMP TABLE tmp_test_normal_batch
ON COMMIT DROP
AS

SELECT *
FROM tmp_test_routed
WHERE route = 'NORMAL';



-- ============================================================
-- 4. Queue LATE rows
-- ============================================================

INSERT INTO control.customer_late_arrival_queue (

    customer_version_id,
    customer_id,
    effective_at

)

SELECT
    customer_version_id,
    customer_id,
    effective_at

FROM tmp_test_routed

WHERE route = 'LATE'

ON CONFLICT (customer_version_id)
DO NOTHING;



-- ============================================================
-- 5. Simulate retry
--
-- Same exact late version is queued again.
-- UNIQUE(customer_version_id) should prevent duplication.
-- ============================================================

INSERT INTO control.customer_late_arrival_queue (

    customer_version_id,
    customer_id,
    effective_at

)

SELECT
    customer_version_id,
    customer_id,
    effective_at

FROM tmp_test_routed

WHERE route = 'LATE'

ON CONFLICT (customer_version_id)
DO NOTHING;



-- ============================================================
-- 6. Verify routing + queue state
-- ============================================================

SELECT
    (
        SELECT COUNT(*)
        FROM tmp_test_normal_batch
    ) AS normal_rows,

    (
        SELECT COUNT(*)
        FROM tmp_test_routed
        WHERE route = 'LATE'
    ) AS late_rows,

    (
        SELECT COUNT(*)
        FROM control.customer_late_arrival_queue
        WHERE customer_version_id = 910002
    ) AS queued_rows;



SELECT
    late_arrival_id,
    customer_version_id,
    customer_id,
    effective_at,
    status,
    repair_action

FROM control.customer_late_arrival_queue

WHERE customer_version_id = 910002;



-- ============================================================
-- 7. Roll back real queue mutation
-- ============================================================

ROLLBACK;



-- ============================================================
-- 8. Prove test queue row disappeared
-- ============================================================

SELECT COUNT(*) AS queue_rows_after_rollback

FROM control.customer_late_arrival_queue

WHERE customer_version_id = 910002;