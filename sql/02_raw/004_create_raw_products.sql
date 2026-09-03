-- ============================================================
-- RetailPulse
-- RAW Products
--
-- One row = one source product record.
--
-- RAW keeps source values as TEXT.
-- ============================================================


CREATE TABLE IF NOT EXISTS raw.products (

    raw_record_id
        BIGINT
        GENERATED ALWAYS AS IDENTITY
        PRIMARY KEY,

    product_id TEXT,

    product_name TEXT,

    category TEXT,

    brand TEXT,

    product_status TEXT,

    source_system TEXT NOT NULL,

    batch_id TEXT NOT NULL,

    ingested_at
        TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP
);