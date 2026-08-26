-- ============================================================
-- RetailPulse
-- Test: stale RUNNING audit becomes FAILED
-- ============================================================


-- Create deliberately stale RUNNING execution
INSERT INTO audit.etl_runs (
    pipeline_name,
    started_at,
    status,
    watermark_before
)
VALUES (
    'stale_reconciliation_test',
    clock_timestamp() - INTERVAL '2 hours',
    'RUNNING',
    71
);


-- Prove it starts as RUNNING
SELECT
    run_id,
    pipeline_name,
    status,
    started_at,
    finished_at
FROM audit.etl_runs
WHERE pipeline_name = 'stale_reconciliation_test'
ORDER BY run_id DESC
LIMIT 1;


-- Run normal reconciliation
\i 'sql/05_etl/004_reconcile_stale_etl_runs.sql'


-- Prove the test run is now FAILED
SELECT
    run_id,
    pipeline_name,
    status,
    started_at,
    finished_at,
    error_message
FROM audit.etl_runs
WHERE pipeline_name = 'stale_reconciliation_test'
ORDER BY run_id DESC
LIMIT 1;