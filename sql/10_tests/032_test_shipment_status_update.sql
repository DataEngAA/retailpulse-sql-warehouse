-- ============================================================
-- TEST 032
-- Shipment status progression
--
-- 9102:
-- IN_TRANSIT -> DELIVERED
--
-- Expected:
-- existing fact updated
-- no duplicate shipment
-- ============================================================


-- 1. BEFORE
SELECT
    shipment_fact_sk,
    shipment_id,
    shipment_status,
    shipped_at,
    delivered_at,
    shipping_cost,
    source_shipment_raw_record_id
FROM warehouse.fact_shipment
WHERE shipment_id = 9102;



-- 2. Simulate later shipment update
INSERT INTO raw.shipments (

    shipment_id,
    order_id,

    carrier,
    tracking_number,
    shipment_status,

    shipped_at,
    delivered_at,

    shipping_cost,

    source_system,
    batch_id

)

SELECT

    '9102',
    '5001',

    'Delhivery',
    'DL-9102',
    'DELIVERED',

    '2026-09-02 09:00:00+05:30',

    '2026-09-04 13:00:00+05:30',

    '80',

    'phase2_demo',
    'shipment_update_demo_001'

WHERE NOT EXISTS (

    SELECT 1

    FROM raw.shipments

    WHERE shipment_id = '9102'
      AND batch_id = 'shipment_update_demo_001'

);



-- 3. Run shipment quality checks
\i 'sql/06_quality/009_detect_shipment_issues.sql'



-- 4. Load new shipment version into staging
\i 'sql/03_staging/014_load_stg_shipments.sql'



-- 5. Show both staged versions
SELECT
    shipment_version_id,
    raw_record_id,
    shipment_id,
    shipment_status,
    shipped_at,
    delivered_at,
    batch_id
FROM staging.stg_shipments
WHERE shipment_id = 9102
ORDER BY shipment_version_id;



-- 6. Reload shipment fact
\i 'sql/05_etl/011_load_fact_shipment.sql'



-- 7. AFTER
SELECT
    shipment_fact_sk,
    shipment_id,
    shipment_status,
    shipped_at,
    delivered_at,
    shipping_cost,
    source_shipment_raw_record_id
FROM warehouse.fact_shipment
WHERE shipment_id = 9102;



-- 8. Must still be exactly one shipment fact
SELECT
    shipment_id,
    COUNT(*) AS row_count
FROM warehouse.fact_shipment
WHERE shipment_id = 9102
GROUP BY shipment_id;



-- 9. Total shipment facts should still be 4
SELECT
    COUNT(*) AS total_shipment_fact_rows
FROM warehouse.fact_shipment;