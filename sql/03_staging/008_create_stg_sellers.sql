CREATE TABLE IF NOT EXISTS staging.stg_sellers (

    seller_version_id
        BIGINT
        GENERATED ALWAYS AS IDENTITY
        PRIMARY KEY,

    raw_record_id BIGINT NOT NULL UNIQUE,

    seller_id BIGINT NOT NULL,

    seller_name TEXT NOT NULL,

    seller_status TEXT,

    country TEXT,

    source_system TEXT NOT NULL,

    batch_id TEXT NOT NULL,

    ingested_at TIMESTAMPTZ NOT NULL
);