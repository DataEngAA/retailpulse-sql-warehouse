CREATE TABLE IF NOT EXISTS raw.customers (
    raw_record_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    customer_id TEXT,
    first_name TEXT,
    last_name TEXT,
    email TEXT,
    phone TEXT,
    date_of_birth TEXT,
    city TEXT,
    state TEXT,
    country TEXT,
    postal_code TEXT,
    signup_date TEXT,
    customer_status TEXT,
    created_at TEXT,
    updated_at TEXT,

    source_system TEXT NOT NULL,
    batch_id TEXT NOT NULL,
    ingested_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);