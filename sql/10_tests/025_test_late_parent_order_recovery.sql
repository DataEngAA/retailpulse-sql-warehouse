-- ============================================================
-- TEST 025
-- Parent order arrives after its order item
--
-- Item 9006 already exists in RAW.
-- It could not enter staging because order 9999 was missing.
--
-- Now order 9999 arrives.
-- ============================================================


-- ------------------------------------------------------------
-- 1. Simulate order 9999 arriving later
-- ------------------------------------------------------------

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

SELECT

    '9999',
    '101',
    'PROCESSING',
    '2026-09-02 10:00:00+05:30',
    '2026-09-02 10:30:00+05:30',
    'INR',
    '50',
    '0',
    'phase2_demo',
    'sales_quality_demo_002'

WHERE NOT EXISTS (

    SELECT 1

    FROM raw.orders

    WHERE order_id = '9999'
      AND batch_id = 'sales_quality_demo_002'

);


-- ------------------------------------------------------------
-- 2. Run order quality detection again
-- ------------------------------------------------------------

\i 'sql/06_quality/003_detect_order_issues.sql'


-- ------------------------------------------------------------
-- 3. Try loading orders into staging again
-- ------------------------------------------------------------

\i 'sql/03_staging/003_load_stg_orders.sql'


-- ------------------------------------------------------------
-- 4. Now retry order items
-- ------------------------------------------------------------

\i 'sql/03_staging/005_load_stg_order_items.sql'


-- ------------------------------------------------------------
-- 5. Show parent order
-- ------------------------------------------------------------

SELECT

    raw_record_id,
    order_id,
    customer_id,
    order_status

FROM staging.stg_orders

WHERE order_id = 9999;


-- ------------------------------------------------------------
-- 6. Show previously blocked child item
-- ------------------------------------------------------------

SELECT

    raw_record_id,
    order_item_id,
    order_id,
    product_id,
    quantity,
    unit_price

FROM staging.stg_order_items

WHERE order_item_id = 9006;