-- ============================================================
-- RetailPulse Phase 2
-- Seed sample sales data for quality testing
--
-- Some rows are GOOD.
-- Some rows are intentionally BAD.
--
-- We will inspect and classify them in the next step.
-- ============================================================


-- ============================================================
-- ORDERS
-- ============================================================


-- GOOD ORDER
INSERT INTO raw.orders (
    order_id,
    customer_id,
    order_status,
    order_created_at,
    order_updated_at,
    currency,
    shipping_amount,
    order_discount_amount,
    source_system,
    batch_id
)
VALUES (
    '5001',
    '101',
    'SHIPPED',
    '2026-09-01 10:00:00+05:30',
    '2026-09-01 14:00:00+05:30',
    'INR',
    '100',
    '200',
    'phase2_demo',
    'sales_quality_demo_001'
);



-- BAD: missing order_id
INSERT INTO raw.orders (
    order_id,
    customer_id,
    order_status,
    order_created_at,
    order_updated_at,
    currency,
    shipping_amount,
    order_discount_amount,
    source_system,
    batch_id
)
VALUES (
    NULL,
    '101',
    'SHIPPED',
    '2026-09-01 11:00:00+05:30',
    '2026-09-01 15:00:00+05:30',
    'INR',
    '100',
    '0',
    'phase2_demo',
    'sales_quality_demo_001'
);



-- BAD: invalid customer_id
INSERT INTO raw.orders (
    order_id,
    customer_id,
    order_status,
    order_created_at,
    order_updated_at,
    currency,
    shipping_amount,
    order_discount_amount,
    source_system,
    batch_id
)
VALUES (
    '5002',
    'ABC',
    'PROCESSING',
    '2026-09-01 12:00:00+05:30',
    '2026-09-01 12:30:00+05:30',
    'INR',
    '80',
    '0',
    'phase2_demo',
    'sales_quality_demo_001'
);



-- BAD: invalid date
INSERT INTO raw.orders (
    order_id,
    customer_id,
    order_status,
    order_created_at,
    order_updated_at,
    currency,
    shipping_amount,
    order_discount_amount,
    source_system,
    batch_id
)
VALUES (
    '5003',
    '101',
    'SHIPPED',
    'not-a-date',
    '2026-09-01 16:00:00+05:30',
    'INR',
    '120',
    '50',
    'phase2_demo',
    'sales_quality_demo_001'
);



-- PARTLY BAD: order itself is useful,
-- but shipping amount is invalid
INSERT INTO raw.orders (
    order_id,
    customer_id,
    order_status,
    order_created_at,
    order_updated_at,
    currency,
    shipping_amount,
    order_discount_amount,
    source_system,
    batch_id
)
VALUES (
    '5004',
    '101',
    'DELIVERED',
    '2026-09-01 13:00:00+05:30',
    '2026-09-02 18:00:00+05:30',
    'INR',
    'twenty',
    '0',
    'phase2_demo',
    'sales_quality_demo_001'
);



-- BAD / SUSPICIOUS: duplicate business order_id
INSERT INTO raw.orders (
    order_id,
    customer_id,
    order_status,
    order_created_at,
    order_updated_at,
    currency,
    shipping_amount,
    order_discount_amount,
    source_system,
    batch_id
)
VALUES (
    '5001',
    '101',
    'SHIPPED',
    '2026-09-01 10:00:00+05:30',
    '2026-09-01 14:00:00+05:30',
    'INR',
    '100',
    '200',
    'phase2_demo',
    'sales_quality_demo_001'
);



-- ============================================================
-- ORDER ITEMS
-- ============================================================


-- GOOD ITEM
INSERT INTO raw.order_items (
    order_item_id,
    order_id,
    product_id,
    seller_id,
    quantity,
    unit_price,
    discount_amount,
    tax_amount,
    source_system,
    batch_id
)
VALUES (
    '9001',
    '5001',
    '301',
    '701',
    '1',
    '50000',
    '1000',
    '9000',
    'phase2_demo',
    'sales_quality_demo_001'
);



-- GOOD ITEM
INSERT INTO raw.order_items (
    order_item_id,
    order_id,
    product_id,
    seller_id,
    quantity,
    unit_price,
    discount_amount,
    tax_amount,
    source_system,
    batch_id
)
VALUES (
    '9002',
    '5001',
    '302',
    '701',
    '2',
    '1000',
    '0',
    '360',
    'phase2_demo',
    'sales_quality_demo_001'
);



-- BAD: negative quantity
INSERT INTO raw.order_items (
    order_item_id,
    order_id,
    product_id,
    seller_id,
    quantity,
    unit_price,
    discount_amount,
    tax_amount,
    source_system,
    batch_id
)
VALUES (
    '9003',
    '5001',
    '303',
    '701',
    '-2',
    '3000',
    '0',
    '540',
    'phase2_demo',
    'sales_quality_demo_001'
);



-- BAD: invalid unit price
INSERT INTO raw.order_items (
    order_item_id,
    order_id,
    product_id,
    seller_id,
    quantity,
    unit_price,
    discount_amount,
    tax_amount,
    source_system,
    batch_id
)
VALUES (
    '9004',
    '5001',
    '304',
    '701',
    '1',
    'abc',
    '0',
    '100',
    'phase2_demo',
    'sales_quality_demo_001'
);



-- BAD: missing product_id
INSERT INTO raw.order_items (
    order_item_id,
    order_id,
    product_id,
    seller_id,
    quantity,
    unit_price,
    discount_amount,
    tax_amount,
    source_system,
    batch_id
)
VALUES (
    '9005',
    '5001',
    NULL,
    '701',
    '1',
    '500',
    '0',
    '90',
    'phase2_demo',
    'sales_quality_demo_001'
);



-- POSSIBLY NOT BAD:
-- item references order 9999, but that order is not present yet
INSERT INTO raw.order_items (
    order_item_id,
    order_id,
    product_id,
    seller_id,
    quantity,
    unit_price,
    discount_amount,
    tax_amount,
    source_system,
    batch_id
)
VALUES (
    '9006',
    '9999',
    '305',
    '701',
    '1',
    '2500',
    '0',
    '450',
    'phase2_demo',
    'sales_quality_demo_001'
);



-- ============================================================
-- SHOW THE TEST DATA
-- ============================================================

SELECT
    raw_record_id,
    order_id,
    customer_id,
    order_status,
    order_created_at,
    shipping_amount,
    batch_id
FROM raw.orders
WHERE batch_id = 'sales_quality_demo_001'
ORDER BY raw_record_id;


SELECT
    raw_record_id,
    order_item_id,
    order_id,
    product_id,
    quantity,
    unit_price,
    batch_id
FROM raw.order_items
WHERE batch_id = 'sales_quality_demo_001'
ORDER BY raw_record_id;