CREATE TABLE IF NOT EXISTS warehouse.fact_order_item (

    order_item_fact_sk
        BIGINT
        GENERATED ALWAYS AS IDENTITY
        PRIMARY KEY,

    -- Business identifiers
    order_item_id BIGINT NOT NULL UNIQUE,

    order_id BIGINT NOT NULL,


    -- Dimension keys
    customer_sk BIGINT NOT NULL,

    product_sk BIGINT NOT NULL,

    seller_sk BIGINT,


    -- Business time
    order_created_at TIMESTAMPTZ NOT NULL,


    -- Measures
    quantity NUMERIC(18,4) NOT NULL,

    unit_price NUMERIC(18,2) NOT NULL,

    discount_amount NUMERIC(18,2),

    tax_amount NUMERIC(18,2),

    gross_amount NUMERIC(18,2) NOT NULL,

    net_amount NUMERIC(18,2) NOT NULL,


    -- Currency
    currency TEXT,


    -- Lineage
    source_order_item_raw_record_id BIGINT NOT NULL,

    source_order_raw_record_id BIGINT NOT NULL,


    loaded_at
        TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,


    CONSTRAINT fk_fact_customer
        FOREIGN KEY (customer_sk)
        REFERENCES warehouse.dim_customer(customer_sk),

    CONSTRAINT fk_fact_product
        FOREIGN KEY (product_sk)
        REFERENCES warehouse.dim_product(product_sk),

    CONSTRAINT fk_fact_seller
        FOREIGN KEY (seller_sk)
        REFERENCES warehouse.dim_seller(seller_sk)
);