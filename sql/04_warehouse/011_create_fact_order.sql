-- ============================================================
-- RetailPulse
-- Integrated Order Fact
--
-- Grain:
-- one row = one order
--
-- Combines order-level metrics from:
--   order items
--   payments
--   shipments
--   returns
-- ============================================================


CREATE TABLE IF NOT EXISTS warehouse.fact_order (

    order_fact_sk
        BIGINT
        GENERATED ALWAYS AS IDENTITY
        PRIMARY KEY,

    order_id BIGINT NOT NULL UNIQUE,

    customer_sk BIGINT NOT NULL,

    order_status TEXT,

    order_created_at TIMESTAMPTZ NOT NULL,

    currency TEXT,


    -- ========================================================
    -- ITEM / SALES METRICS
    -- ========================================================

    item_line_count BIGINT NOT NULL,

    units_sold NUMERIC(18,4) NOT NULL,

    item_gross_amount NUMERIC(18,2) NOT NULL,

    item_net_amount NUMERIC(18,2) NOT NULL,


    -- ========================================================
    -- ORDER-LEVEL FINANCIALS
    -- ========================================================

    shipping_amount NUMERIC(18,2) NOT NULL,

    order_discount_amount NUMERIC(18,2) NOT NULL,

    expected_order_amount NUMERIC(18,2) NOT NULL,


    -- ========================================================
    -- PAYMENT METRICS
    -- ========================================================

    payment_attempt_count BIGINT NOT NULL,

    successful_payment_count BIGINT NOT NULL,

    failed_payment_count BIGINT NOT NULL,

    successful_payment_amount NUMERIC(18,2) NOT NULL,


    -- ========================================================
    -- SHIPMENT METRICS
    -- ========================================================

    shipment_count BIGINT NOT NULL,

    delivered_shipment_count BIGINT NOT NULL,

    in_transit_shipment_count BIGINT NOT NULL,

    shipped_shipment_count BIGINT NOT NULL,


    -- ========================================================
    -- RETURN METRICS
    -- ========================================================

    return_request_count BIGINT NOT NULL,

    active_return_count BIGINT NOT NULL,

    completed_return_count BIGINT NOT NULL,

    active_return_quantity NUMERIC(18,4) NOT NULL,

    completed_return_quantity NUMERIC(18,4) NOT NULL,

    completed_refund_amount NUMERIC(18,2) NOT NULL,


    -- ========================================================
    -- RECONCILIATION METRICS
    -- ========================================================

    payment_vs_expected_difference
        NUMERIC(18,2) NOT NULL,

    net_sales_after_refunds
        NUMERIC(18,2) NOT NULL,

    net_cash_after_refunds
        NUMERIC(18,2) NOT NULL,


    -- ========================================================
    -- LINEAGE
    -- ========================================================

    source_order_raw_record_id BIGINT NOT NULL,

    loaded_at
        TIMESTAMPTZ
        NOT NULL
        DEFAULT CURRENT_TIMESTAMP,


    CONSTRAINT fk_fact_order_customer
        FOREIGN KEY (customer_sk)
        REFERENCES warehouse.dim_customer(customer_sk)
);