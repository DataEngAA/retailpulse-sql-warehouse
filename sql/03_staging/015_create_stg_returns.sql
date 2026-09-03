CREATE TABLE IF NOT EXISTS staging.stg_returns (

    return_version_id
        BIGINT
        GENERATED ALWAYS AS IDENTITY
        PRIMARY KEY,

    raw_record_id BIGINT NOT NULL UNIQUE,

    return_id BIGINT NOT NULL,

    order_item_id BIGINT NOT NULL,

    return_status TEXT,

    return_quantity NUMERIC(18,4) NOT NULL,

    refund_amount NUMERIC(18,2) NOT NULL,

    return_reason TEXT,

    requested_at TIMESTAMPTZ NOT NULL,

    completed_at TIMESTAMPTZ,

    source_system TEXT NOT NULL,

    batch_id TEXT NOT NULL,

    ingested_at TIMESTAMPTZ NOT NULL
);