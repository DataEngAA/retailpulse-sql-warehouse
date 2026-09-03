CREATE TABLE IF NOT EXISTS warehouse.dim_seller (

    seller_sk
        BIGINT
        GENERATED ALWAYS AS IDENTITY
        PRIMARY KEY,

    seller_id BIGINT NOT NULL UNIQUE,

    seller_name TEXT NOT NULL,

    seller_status TEXT,

    country TEXT,

    source_raw_record_id BIGINT NOT NULL,

    created_at
        TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at
        TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP
);