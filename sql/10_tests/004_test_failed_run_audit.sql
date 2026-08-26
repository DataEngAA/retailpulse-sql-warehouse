-- ============================================================
-- RetailPulse
-- Test: audit row created inside failed ETL transaction
-- is rolled back
--
-- Purpose:
-- prove why failed-run auditing needs a separate transaction.
-- ============================================================


BEGIN;


-- ============================================================
-- 1. Capture current watermark
-- ============================================================

CREATE TEMP TABLE tmp_test_context (
    watermark_before BIGINT NOT NULL
)
ON COMMIT DROP;


INSERT INTO tmp_test_context (
    watermark_before
)

SELECT
    last_processed_version_id

FROM control.pipeline_watermark

WHERE pipeline_name = 'dim_customer_incremental';



-- ============================================================
-- 2. Create a RUNNING audit row
-- ============================================================

INSERT INTO audit.etl_runs (
    pipeline_name,
    status,
    watermark_before
)

SELECT
    'dim_customer_incremental_test_failure',
    'RUNNING',
    watermark_before

FROM tmp_test_context;



-- ============================================================
-- 3. Prove the RUNNING row exists INSIDE this transaction
-- ============================================================

SELECT
    run_id,
    pipeline_name,
    status,
    watermark_before,
    started_at

FROM audit.etl_runs

WHERE pipeline_name = 'dim_customer_incremental_test_failure'

ORDER BY run_id DESC

LIMIT 1;



-- ============================================================
-- 4. Force a failure
--
-- This temporary table only accepts violation_count = 0.
-- We deliberately insert 1.
-- ============================================================

CREATE TEMP TABLE tmp_forced_failure (
    violation_count INTEGER NOT NULL,

    CONSTRAINT forced_etl_failure
        CHECK (violation_count = 0)
)
ON COMMIT DROP;


INSERT INTO tmp_forced_failure (
    violation_count
)
VALUES (1);



-- ============================================================
-- 5. Transaction should now be aborted.
--
-- This ROLLBACK removes:
--   - temp objects
--   - RUNNING audit row
-- ============================================================

ROLLBACK;



-- ============================================================
-- 6. After rollback, prove the audit row disappeared
-- ============================================================

SELECT
    run_id,
    pipeline_name,
    status,
    watermark_before,
    started_at

FROM audit.etl_runs

WHERE pipeline_name = 'dim_customer_incremental_test_failure'

ORDER BY run_id DESC;