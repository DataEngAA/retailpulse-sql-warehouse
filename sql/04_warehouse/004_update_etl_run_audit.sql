-- ============================================================
-- RetailPulse
-- Update ETL audit model for durable RUNNING records
-- ============================================================


-- A RUNNING/FAILED execution may not yet have established
-- its transactional starting watermark.
ALTER TABLE audit.etl_runs
ALTER COLUMN watermark_before DROP NOT NULL;


-- Successful runs MUST have complete watermark information.
ALTER TABLE audit.etl_runs
ADD CONSTRAINT chk_successful_run_watermarks
CHECK (
    status <> 'SUCCESS'
    OR (
        watermark_before IS NOT NULL
        AND watermark_after IS NOT NULL
    )
);