CREATE TABLE IF NOT EXISTS staging.stg_shipments (

    shipment_version_id
        BIGINT
        GENERATED ALWAYS AS IDENTITY
        PRIMARY KEY,

    raw_record_id BIGINT NOT NULL UNIQUE,

    shipment_id BIGINT NOT NULL,

    order_id BIGINT NOT NULL,

    carrier TEXT,

    tracking_number TEXT,

    shipment_status TEXT,

    shipped_at TIMESTAMPTZ NOT NULL,

    delivered_at TIMESTAMPTZ,

    shipping_cost NUMERIC(18,2),

    source_system TEXT NOT NULL,

    batch_id TEXT NOT NULL,

    ingested_at TIMESTAMPTZ NOT NULL
);