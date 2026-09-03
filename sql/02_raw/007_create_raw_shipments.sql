-- ============================================================
-- RetailPulse
-- RAW Shipments
--
-- Grain:
-- one row = one source shipment record/version
--
-- RAW keeps source values as TEXT.
-- ============================================================


CREATE TABLE IF NOT EXISTS raw.shipments (

    raw_record_id
        BIGINT
        GENERATED ALWAYS AS IDENTITY
        PRIMARY KEY,


    shipment_id TEXT,

    order_id TEXT,

    carrier TEXT,

    tracking_number TEXT,

    shipment_status TEXT,

    shipped_at TEXT,

    delivered_at TEXT,

    shipping_cost TEXT,


    source_system TEXT NOT NULL,

    batch_id TEXT NOT NULL,

    ingested_at
        TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP
);