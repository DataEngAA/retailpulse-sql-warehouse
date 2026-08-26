CREATE TABLE IF NOT EXISTS warehouse.dim_customer (
    customer_sk BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    customer_id BIGINT NOT NULL,

    first_name TEXT,
    last_name TEXT,
    email TEXT,
    phone TEXT,
    date_of_birth DATE,
    signup_date DATE,

    city TEXT,
    state TEXT,
    country TEXT,
    postal_code TEXT,
    customer_status TEXT,

    valid_from TIMESTAMPTZ NOT NULL,
    valid_to TIMESTAMPTZ,
    is_current BOOLEAN NOT NULL,

    source_raw_record_id BIGINT NOT NULL,

    warehouse_created_at TIMESTAMPTZ NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_customer_validity
        CHECK (
            valid_to IS NULL
            OR valid_to > valid_from
        )
);