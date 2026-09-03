-- ============================================================
-- RetailPulse V3
-- Test queue + watermark transaction atomicity
--
-- We deliberately:
--   1. queue a synthetic late version
--   2. advance the REAL customer watermark
--   3. force a failure
--   4. rollback
--
-- Expected:
--   queue row disappears
--   watermark returns to original value
-- ============================================================


\set ON_ERROR_STOP off


-- ============================================================
-- 1. Capture starting watermark outside test transaction
-- ============================================================

DROP TABLE IF EXISTS tmp_atomicity_context;


CREATE TEMP TABLE tmp_atomicity_context
ON COMMIT PRESERVE ROWS
AS

SELECT
    last_processed_version_id
        AS watermark_before,

    last_processed_version_id + 2
        AS synthetic_late_version_id,

    last_processed_version_id + 3
        AS synthetic_batch_max

FROM control.pipeline_watermark

WHERE pipeline_name = 'dim_customer_incremental';



SELECT *
FROM tmp_atomicity_context;



-- ============================================================
-- 2. Begin simulated V2 transaction
-- ============================================================

BEGIN;



-- ============================================================
-- 3. Queue synthetic late arrival
-- ============================================================

INSERT INTO control.customer_late_arrival_queue (

    customer_version_id,
    customer_id,
    effective_at

)

SELECT
    synthetic_late_version_id,
    101,
    '2026-08-29 15:00:00+05:30'::TIMESTAMPTZ

FROM tmp_atomicity_context

ON CONFLICT (customer_version_id)
DO NOTHING;



-- ============================================================
-- 4. Simulate normal pipeline advancing watermark
-- ============================================================

UPDATE control.pipeline_watermark w

SET
    last_processed_version_id =
        c.synthetic_batch_max,

    updated_at =
        clock_timestamp()

FROM tmp_atomicity_context c

WHERE w.pipeline_name =
      'dim_customer_incremental';



-- ============================================================
-- 5. Verify both changes exist INSIDE transaction
-- ============================================================

SELECT
    (
        SELECT COUNT(*)

        FROM control.customer_late_arrival_queue q

        JOIN tmp_atomicity_context c
            ON q.customer_version_id =
               c.synthetic_late_version_id
    ) AS queued_rows_inside_transaction,


    (
        SELECT last_processed_version_id

        FROM control.pipeline_watermark

        WHERE pipeline_name =
              'dim_customer_incremental'
    ) AS watermark_inside_transaction;



-- ============================================================
-- 6. Force transaction failure
-- ============================================================

CREATE TEMP TABLE tmp_force_atomicity_failure (

    violation_count INTEGER NOT NULL,

    CONSTRAINT forced_queue_watermark_failure
        CHECK (violation_count = 0)

)
ON COMMIT DROP;


INSERT INTO tmp_force_atomicity_failure
VALUES (1);



-- Transaction is now aborted
ROLLBACK;



-- ============================================================
-- 7. Prove BOTH changes rolled back
-- ============================================================

SELECT
    c.watermark_before,

    (
        SELECT last_processed_version_id

        FROM control.pipeline_watermark

        WHERE pipeline_name =
              'dim_customer_incremental'
    ) AS watermark_after_rollback,

    (
        SELECT COUNT(*)

        FROM control.customer_late_arrival_queue q

        WHERE q.customer_version_id =
              c.synthetic_late_version_id
    ) AS queued_rows_after_rollback

FROM tmp_atomicity_context c;



DROP TABLE tmp_atomicity_context;