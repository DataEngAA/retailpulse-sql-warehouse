-- ============================================================
-- RetailPulse
-- RAW Payments
--
-- Grain:
-- one row = one source payment event
--
-- RAW keeps source values as TEXT.
-- ============================================================


CREATE TABLE IF NOT EXISTS raw.payments (

    raw_record_id
        BIGINT
        GENERATED ALWAYS AS IDENTITY
        PRIMARY KEY,


    -- Business identifiers
    payment_id TEXT,

    order_id TEXT,


    -- Payment details
    payment_type TEXT,
    payment_status TEXT,
    payment_method TEXT,

    payment_amount TEXT,
    currency TEXT,

    payment_created_at TEXT,

    transaction_reference TEXT,


    -- Source metadata
    source_system TEXT NOT NULL,

    batch_id TEXT NOT NULL,

    ingested_at
        TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP
);