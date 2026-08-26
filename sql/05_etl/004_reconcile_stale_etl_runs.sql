-- ============================================================
-- RetailPulse
-- Reconcile stale ETL RUNNING records
--
-- Policy:
-- A RUNNING execution older than 30 minutes is considered
-- abandoned/failed.
-- ============================================================


WITH stale_runs AS (

    SELECT
        run_id

    FROM audit.etl_runs

    WHERE status = 'RUNNING'

      AND started_at <
          clock_timestamp() - INTERVAL '30 minutes'

)

UPDATE audit.etl_runs e

SET
    status = 'FAILED',

    finished_at = clock_timestamp(),

    error_message =
        'Reconciled stale RUNNING execution after 30-minute timeout.'

FROM stale_runs s

WHERE e.run_id = s.run_id

RETURNING
    e.run_id,
    e.pipeline_name,
    e.status,
    e.started_at,
    e.finished_at,
    e.watermark_before,
    e.watermark_after,
    e.error_message;