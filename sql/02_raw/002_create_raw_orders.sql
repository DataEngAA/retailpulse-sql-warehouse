-- ============================================================
-- RetailPulse
-- RAW Orders
--
-- RAW preserves source truth.
-- Source fields remain TEXT so malformed values can land
-- without crashing ingestion.
-- ============================================================


CREATE TABLE IF NOT EXISTS raw.orders (

    raw_record_id
        BIGINT
        GENERATED ALWAYS AS IDENTITY
        PRIMARY KEY,


    -- Business identifiers
    order_id TEXT,

    customer_id TEXT,


    -- Order lifecycle
    order_status TEXT,

    order_created_at TEXT,

    order_updated_at TEXT,


    -- Commercial attributes
    currency TEXT,

    shipping_amount TEXT,

    order_discount_amount TEXT,


    -- Ingestion metadata
    source_system TEXT NOT NULL,

    batch_id TEXT NOT NULL,

    ingested_at
        TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP

);