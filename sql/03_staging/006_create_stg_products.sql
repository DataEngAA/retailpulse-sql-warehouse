CREATE TABLE IF NOT EXISTS staging.stg_products (

    product_version_id
        BIGINT
        GENERATED ALWAYS AS IDENTITY
        PRIMARY KEY,

    raw_record_id BIGINT NOT NULL UNIQUE,

    product_id BIGINT NOT NULL,

    product_name TEXT NOT NULL,

    category TEXT,

    brand TEXT,

    product_status TEXT,

    source_system TEXT NOT NULL,

    batch_id TEXT NOT NULL,

    ingested_at TIMESTAMPTZ NOT NULL
);