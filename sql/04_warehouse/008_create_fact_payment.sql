CREATE TABLE IF NOT EXISTS warehouse.fact_payment (

    payment_fact_sk
        BIGINT
        GENERATED ALWAYS AS IDENTITY
        PRIMARY KEY,

    payment_id BIGINT NOT NULL UNIQUE,

    order_id BIGINT NOT NULL,

    customer_sk BIGINT NOT NULL,

    payment_type TEXT,

    payment_status TEXT,

    payment_method TEXT,

    payment_amount NUMERIC(18,2) NOT NULL,

    currency TEXT,

    payment_created_at TIMESTAMPTZ NOT NULL,

    transaction_reference TEXT,

    source_payment_raw_record_id BIGINT NOT NULL,

    source_order_raw_record_id BIGINT NOT NULL,

    loaded_at
        TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_fact_payment_amount
        CHECK (payment_amount >= 0),

    CONSTRAINT fk_fact_payment_customer
        FOREIGN KEY (customer_sk)
        REFERENCES warehouse.dim_customer(customer_sk)
);