-- ============================================================
-- TEST 028
-- Existing order item receives a correction
--
-- Original:
--   9002 quantity = 2
--
-- Correction:
--   9002 quantity = 3
--
-- Expected:
--   fact row UPDATED
--   no duplicate fact row
-- ============================================================


-- ============================================================
-- 1. Show fact BEFORE correction
-- ============================================================

SELECT
    order_item_id,
    quantity,
    unit_price,
    gross_amount,
    net_amount,
    source_order_item_raw_record_id
FROM warehouse.fact_order_item
WHERE order_item_id = 9002;



-- ============================================================
-- 2. Simulate a new source version of item 9002
-- ============================================================

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

SELECT

    '9002',
    '5001',
    '302',
    '701',

    '3',
    '1000',
    '0',
    '360',

    'phase2_demo',
    'sales_correction_demo_001'

WHERE NOT EXISTS (

    SELECT 1

    FROM raw.order_items

    WHERE order_item_id = '9002'
      AND batch_id = 'sales_correction_demo_001'

);



-- ============================================================
-- 3. Run quality checks
-- ============================================================

\i 'sql/06_quality/004_detect_order_item_issues.sql'



-- ============================================================
-- 4. Load new usable version into staging
-- ============================================================

\i 'sql/03_staging/005_load_stg_order_items.sql'



-- ============================================================
-- 5. Show all staged versions of 9002
-- ============================================================

SELECT
    order_item_version_id,
    raw_record_id,
    order_item_id,
    quantity,
    unit_price,
    batch_id
FROM staging.stg_order_items
WHERE order_item_id = 9002
ORDER BY order_item_version_id;



-- ============================================================
-- 6. Rerun fact loader
--
-- It should UPDATE existing 9002,
-- not insert another business fact.
-- ============================================================

\i 'sql/05_etl/009_load_fact_order_item.sql'



-- ============================================================
-- 7. Show fact AFTER correction
-- ============================================================

SELECT
    order_item_fact_sk,
    order_item_id,
    quantity,
    unit_price,
    discount_amount,
    tax_amount,
    gross_amount,
    net_amount,
    source_order_item_raw_record_id
FROM warehouse.fact_order_item
WHERE order_item_id = 9002;



-- ============================================================
-- 8. Prove we still have one fact row
-- ============================================================

SELECT
    order_item_id,
    COUNT(*) AS row_count
FROM warehouse.fact_order_item
WHERE order_item_id = 9002
GROUP BY order_item_id;



-- ============================================================
-- 9. Total fact count should still be 3
-- ============================================================

SELECT
    COUNT(*) AS total_fact_rows
FROM warehouse.fact_order_item;