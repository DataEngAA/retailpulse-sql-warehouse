-- ============================================================
-- RetailPulse
-- ETL Run Audit Table
--
-- Stores operational metadata for pipeline executions.
-- ============================================================

CREATE TABLE IF NOT EXISTS audit.etl_runs (

    run_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    pipeline_name TEXT NOT NULL,

    started_at TIMESTAMPTZ NOT NULL
        DEFAULT clock_timestamp(),

    finished_at TIMESTAMPTZ,

    status TEXT NOT NULL,

    watermark_before BIGINT NOT NULL,
    watermark_after BIGINT,

    rows_in_batch INTEGER NOT NULL
        DEFAULT 0,

    scd2_rows_inserted INTEGER NOT NULL
        DEFAULT 0,

    type1_customers_affected INTEGER NOT NULL
        DEFAULT 0,

    error_message TEXT,

    CONSTRAINT chk_etl_run_status
        CHECK (
            status IN (
                'RUNNING',
                'SUCCESS',
                'FAILED'
            )
        ),

    CONSTRAINT chk_etl_run_counts
        CHECK (
            rows_in_batch >= 0
            AND scd2_rows_inserted >= 0
            AND type1_customers_affected >= 0
        )
);