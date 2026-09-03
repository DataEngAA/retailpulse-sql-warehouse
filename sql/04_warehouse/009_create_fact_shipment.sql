CREATE TABLE IF NOT EXISTS warehouse.fact_shipment (

    shipment_fact_sk
        BIGINT
        GENERATED ALWAYS AS IDENTITY
        PRIMARY KEY,

    shipment_id BIGINT NOT NULL UNIQUE,

    order_id BIGINT NOT NULL,

    customer_sk BIGINT NOT NULL,

    carrier TEXT,

    tracking_number TEXT,

    shipment_status TEXT,

    shipped_at TIMESTAMPTZ NOT NULL,

    delivered_at TIMESTAMPTZ,

    shipping_cost NUMERIC(18,2),

    source_shipment_raw_record_id BIGINT NOT NULL,

    source_order_raw_record_id BIGINT NOT NULL,

    loaded_at
        TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_fact_shipment_customer
        FOREIGN KEY (customer_sk)
        REFERENCES warehouse.dim_customer(customer_sk),

    CONSTRAINT chk_shipment_dates
        CHECK (
            delivered_at IS NULL
            OR delivered_at >= shipped_at
        )
);