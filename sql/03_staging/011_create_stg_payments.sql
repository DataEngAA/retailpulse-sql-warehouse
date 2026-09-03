CREATE TABLE IF NOT EXISTS staging.stg_payments (

    payment_version_id
        BIGINT
        GENERATED ALWAYS AS IDENTITY
        PRIMARY KEY,

    raw_record_id BIGINT NOT NULL UNIQUE,

    payment_id BIGINT NOT NULL,

    order_id BIGINT NOT NULL,

    payment_type TEXT,

    payment_status TEXT,

    payment_method TEXT,

    payment_amount NUMERIC(18,2) NOT NULL,

    currency TEXT,

    payment_created_at TIMESTAMPTZ NOT NULL,

    transaction_reference TEXT,

    source_system TEXT NOT NULL,

    batch_id TEXT NOT NULL,

    ingested_at TIMESTAMPTZ NOT NULL
);