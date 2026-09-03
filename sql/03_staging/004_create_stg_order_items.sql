-- ============================================================
-- RetailPulse
-- STAGING Order Items
--
-- Clean and correctly typed order-item records.
-- ============================================================

CREATE TABLE IF NOT EXISTS staging.stg_order_items (

    order_item_version_id
        BIGINT
        GENERATED ALWAYS AS IDENTITY
        PRIMARY KEY,

    -- Link back to RAW
    raw_record_id BIGINT NOT NULL UNIQUE,

    -- Business IDs
    order_item_id BIGINT NOT NULL,

    order_id BIGINT NOT NULL,

    product_id BIGINT NOT NULL,

    seller_id BIGINT,


    -- Measures
    quantity NUMERIC(18,4) NOT NULL,

    unit_price NUMERIC(18,2) NOT NULL,

    discount_amount NUMERIC(18,2),

    tax_amount NUMERIC(18,2),


    -- Source metadata
    source_system TEXT NOT NULL,

    batch_id TEXT NOT NULL,

    ingested_at TIMESTAMPTZ NOT NULL
);