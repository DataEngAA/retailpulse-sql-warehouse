CREATE TABLE IF NOT EXISTS staging.stg_customer_versions (
    customer_version_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    raw_record_id BIGINT NOT NULL UNIQUE,
    customer_id BIGINT NOT NULL,

    first_name TEXT,
    last_name TEXT,
    email TEXT,
    phone TEXT,
    date_of_birth DATE,

    city TEXT,
    state TEXT,
    country TEXT,
    postal_code TEXT,

    signup_date DATE,
    customer_status TEXT,

    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ,

    effective_at TIMESTAMPTZ NOT NULL,
    timestamp_source TEXT NOT NULL,

    source_system TEXT NOT NULL,
    batch_id TEXT NOT NULL,
    ingested_at TIMESTAMPTZ NOT NULL,

    staged_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_timestamp_source
        CHECK (
            timestamp_source IN (
                'updated_at',
                'created_at',
                'ingested_at'
            )
        )
);