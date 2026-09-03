CREATE TABLE IF NOT EXISTS staging.stg_orders (

    order_version_id
        BIGINT
        GENERATED ALWAYS AS IDENTITY
        PRIMARY KEY,

    -- Link back to RAW
    raw_record_id BIGINT NOT NULL UNIQUE,

    -- Clean business fields
    order_id BIGINT NOT NULL,

    customer_id BIGINT NOT NULL,

    order_status TEXT,

    order_created_at TIMESTAMPTZ NOT NULL,

    order_updated_at TIMESTAMPTZ,

    currency TEXT,

    shipping_amount NUMERIC(18,2),

    order_discount_amount NUMERIC(18,2),

    -- Source metadata
    source_system TEXT NOT NULL,

    batch_id TEXT NOT NULL,

    ingested_at TIMESTAMPTZ NOT NULL
);