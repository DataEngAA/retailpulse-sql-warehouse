-- ============================================================
-- RetailPulse
-- RAW Order Items
--
-- Source grain:
-- one row = one order line/item.
--
-- RAW values remain TEXT intentionally.
-- ============================================================


CREATE TABLE IF NOT EXISTS raw.order_items (

    raw_record_id
        BIGINT
        GENERATED ALWAYS AS IDENTITY
        PRIMARY KEY,


    -- Business identifiers
    order_item_id TEXT,

    order_id TEXT,

    product_id TEXT,

    seller_id TEXT,


    -- Measures
    quantity TEXT,

    unit_price TEXT,

    discount_amount TEXT,

    tax_amount TEXT,


    -- Ingestion metadata
    source_system TEXT NOT NULL,

    batch_id TEXT NOT NULL,

    ingested_at
        TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP

);