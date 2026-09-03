CREATE TABLE IF NOT EXISTS warehouse.dim_product (

    product_sk
        BIGINT
        GENERATED ALWAYS AS IDENTITY
        PRIMARY KEY,

    product_id BIGINT NOT NULL UNIQUE,

    product_name TEXT NOT NULL,

    category TEXT,

    brand TEXT,

    product_status TEXT,

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