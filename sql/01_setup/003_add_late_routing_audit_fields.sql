-- ============================================================
-- RetailPulse
-- Add observability for late-arrival routing
-- ============================================================


-- ============================================================
-- 1. Audit metric:
-- how many staging versions were handed to V3
-- ============================================================

ALTER TABLE audit.etl_runs

ADD COLUMN late_rows_queued
    INTEGER
    NOT NULL
    DEFAULT 0;



ALTER TABLE audit.etl_runs

ADD CONSTRAINT chk_etl_late_rows_queued

CHECK (
    late_rows_queued >= 0
);



-- ============================================================
-- 2. Queue lineage:
-- which ETL execution detected this late version?
-- ============================================================

ALTER TABLE control.customer_late_arrival_queue

ADD COLUMN detected_run_id
    BIGINT;



ALTER TABLE control.customer_late_arrival_queue

ADD CONSTRAINT fk_customer_late_detected_run

FOREIGN KEY (detected_run_id)

REFERENCES audit.etl_runs(run_id);