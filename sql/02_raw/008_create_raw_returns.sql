-- ============================================================
-- RetailPulse
-- RAW Returns
--
-- Grain:
-- one row = one source return request/event
--
-- RAW keeps source values as TEXT.
-- ============================================================


CREATE TABLE IF NOT EXISTS raw.returns (

    raw_record_id
        BIGINT
        GENERATED ALWAYS AS IDENTITY
        PRIMARY KEY,

    return_id TEXT,

    order_item_id TEXT,

    return_status TEXT,

    return_quantity TEXT,

    refund_amount TEXT,

    return_reason TEXT,

    requested_at TEXT,

    completed_at TEXT,

    source_system TEXT NOT NULL,

    batch_id TEXT NOT NULL,

    ingested_at
        TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP
);