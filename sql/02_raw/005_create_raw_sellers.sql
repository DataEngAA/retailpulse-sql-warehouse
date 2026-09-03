CREATE TABLE IF NOT EXISTS raw.sellers (

    raw_record_id
        BIGINT
        GENERATED ALWAYS AS IDENTITY
        PRIMARY KEY,

    seller_id TEXT,

    seller_name TEXT,

    seller_status TEXT,

    country TEXT,

    source_system TEXT NOT NULL,

    batch_id TEXT NOT NULL,

    ingested_at
        TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP
);