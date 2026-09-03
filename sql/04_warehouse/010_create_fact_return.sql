CREATE TABLE IF NOT EXISTS warehouse.fact_return (

    return_fact_sk
        BIGINT
        GENERATED ALWAYS AS IDENTITY
        PRIMARY KEY,

    return_id BIGINT NOT NULL UNIQUE,

    order_item_id BIGINT NOT NULL,

    order_id BIGINT NOT NULL,

    customer_sk BIGINT NOT NULL,

    product_sk BIGINT NOT NULL,

    seller_sk BIGINT,

    return_status TEXT,

    return_quantity NUMERIC(18,4) NOT NULL,

    refund_amount NUMERIC(18,2) NOT NULL,

    return_reason TEXT,

    requested_at TIMESTAMPTZ NOT NULL,

    completed_at TIMESTAMPTZ,

    source_return_raw_record_id BIGINT NOT NULL,

    loaded_at
        TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_return_quantity_positive
        CHECK (return_quantity > 0),

    CONSTRAINT chk_return_refund_nonnegative
        CHECK (refund_amount >= 0),

    CONSTRAINT chk_return_dates
        CHECK (
            completed_at IS NULL
            OR completed_at >= requested_at
        ),

    CONSTRAINT fk_return_customer
        FOREIGN KEY (customer_sk)
        REFERENCES warehouse.dim_customer(customer_sk),

    CONSTRAINT fk_return_product
        FOREIGN KEY (product_sk)
        REFERENCES warehouse.dim_product(product_sk),

    CONSTRAINT fk_return_seller
        FOREIGN KEY (seller_sk)
        REFERENCES warehouse.dim_seller(seller_sk)
);