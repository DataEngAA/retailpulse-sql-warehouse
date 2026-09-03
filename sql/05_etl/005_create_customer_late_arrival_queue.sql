-- ============================================================
-- RetailPulse
-- Customer late-arrival repair queue
--
-- Late staging versions are persisted here so they do not
-- permanently block the normal incremental watermark.
-- ============================================================


CREATE TABLE IF NOT EXISTS control.customer_late_arrival_queue (

    late_arrival_id
        BIGINT
        GENERATED ALWAYS AS IDENTITY
        PRIMARY KEY,


    -- Original staging version being deferred to V3
    customer_version_id
        BIGINT
        NOT NULL,


    customer_id
        BIGINT
        NOT NULL,


    effective_at
        TIMESTAMPTZ
        NOT NULL,


    status
        TEXT
        NOT NULL
        DEFAULT 'PENDING',


    repair_action
        TEXT,


    detected_at
        TIMESTAMPTZ
        NOT NULL
        DEFAULT clock_timestamp(),


    processed_at
        TIMESTAMPTZ,


    error_message
        TEXT,


    -- Same staging version must never be queued twice
    CONSTRAINT uq_customer_late_arrival_version
        UNIQUE (customer_version_id),


    CONSTRAINT chk_customer_late_arrival_status
        CHECK (
            status IN (
                'PENDING',
                'SUCCESS',
                'FAILED'
            )
        ),


    CONSTRAINT chk_customer_late_repair_action
        CHECK (
            repair_action IS NULL

            OR repair_action IN (
                'NO_SCD2_CHANGE',
                'SPLIT_INSERT',
                'MERGE_WITH_NEXT'
            )
        ),


    CONSTRAINT chk_customer_late_processed_state
        CHECK (

            (
                status = 'PENDING'
                AND processed_at IS NULL
            )

            OR

            (
                status IN ('SUCCESS', 'FAILED')
                AND processed_at IS NOT NULL
            )

        )
);