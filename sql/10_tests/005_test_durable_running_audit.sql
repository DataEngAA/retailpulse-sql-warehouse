-- ============================================================
-- RetailPulse
-- Test: committed RUNNING audit survives ETL rollback
-- ============================================================


DROP TABLE IF EXISTS tmp_test_run_context;


CREATE TEMP TABLE tmp_test_run_context (
    run_id BIGINT NOT NULL
)
ON COMMIT PRESERVE ROWS;



-- ============================================================
-- TRANSACTION A
-- Commit RUNNING audit first
-- ============================================================

BEGIN;


WITH new_run AS (

    INSERT INTO audit.etl_runs (
        pipeline_name,
        status,
        watermark_before
    )

    VALUES (
        'dim_customer_incremental_failure_boundary_test',
        'RUNNING',
        NULL
    )

    RETURNING run_id

)

INSERT INTO tmp_test_run_context (
    run_id
)

SELECT run_id
FROM new_run;


COMMIT;



-- Prove RUNNING row is now durable
SELECT
    e.run_id,
    e.pipeline_name,
    e.status,
    e.watermark_before
FROM audit.etl_runs e

JOIN tmp_test_run_context r
    ON e.run_id = r.run_id;



-- ============================================================
-- TRANSACTION B
-- Simulate ETL work, then force failure
-- ============================================================

BEGIN;


-- Show current real watermark
SELECT
    last_processed_version_id
FROM control.pipeline_watermark
WHERE pipeline_name = 'dim_customer_incremental'
FOR UPDATE;


-- Fake warehouse-side change inside transaction.
-- We deliberately do NOT touch real warehouse data.
CREATE TEMP TABLE tmp_fake_etl_work (
    id INTEGER
)
ON COMMIT DROP;


INSERT INTO tmp_fake_etl_work
VALUES (1);


-- Force failure
CREATE TEMP TABLE tmp_forced_failure (
    violation_count INTEGER NOT NULL,

    CONSTRAINT forced_transaction_b_failure
        CHECK (violation_count = 0)
)
ON COMMIT DROP;


INSERT INTO tmp_forced_failure (
    violation_count
)
VALUES (1);


-- Transaction B is aborted here.
ROLLBACK;



-- ============================================================
-- AFTER ROLLBACK
-- RUNNING audit should still exist
-- ============================================================

SELECT
    e.run_id,
    e.pipeline_name,
    e.status,
    e.watermark_before,
    e.watermark_after,
    e.finished_at
FROM audit.etl_runs e

JOIN tmp_test_run_context r
    ON e.run_id = r.run_id;


-- Real pipeline watermark must still be unchanged
SELECT
    pipeline_name,
    last_processed_version_id
FROM control.pipeline_watermark
WHERE pipeline_name = 'dim_customer_incremental';


DROP TABLE tmp_test_run_context;