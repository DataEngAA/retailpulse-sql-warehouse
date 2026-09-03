-- ============================================================
-- TEST 040
-- Integrated Order Child-Fact Refresh
--
-- Scenario:
-- shipment 9103 for order 9999
--
-- SHIPPED -> DELIVERED
--
-- Expected:
-- shipment fact updates
-- integrated order fact refreshes
-- same order_fact_sk
-- no duplicate order
-- ============================================================


-- ============================================================
-- 1. BEFORE
-- ============================================================

SELECT
    order_fact_sk,
    order_id,

    shipment_count,
    delivered_shipment_count,
    in_transit_shipment_count,
    shipped_shipment_count,

    loaded_at

FROM warehouse.fact_order

WHERE order_id = 9999;



-- ============================================================
-- 2. Add newer RAW shipment version
-- ============================================================

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

    '9103',
    '9999',

    'BlueDart',
    'BD-9103',

    'DELIVERED',

    '2026-09-02 14:00:00+05:30',
    '2026-09-05 16:00:00+05:30',

    '50',

    'phase3_demo',
    'integrated_child_refresh_001'

WHERE NOT EXISTS (

    SELECT 1

    FROM raw.shipments

    WHERE shipment_id = '9103'
      AND batch_id = 'integrated_child_refresh_001'

);



-- ============================================================
-- 3. Shipment quality
-- ============================================================

\i 'sql/06_quality/009_detect_shipment_issues.sql'



-- ============================================================
-- 4. Shipment staging
-- ============================================================

\i 'sql/03_staging/014_load_stg_shipments.sql'



-- ============================================================
-- 5. Refresh shipment fact
-- ============================================================

\i 'sql/05_etl/011_load_fact_shipment.sql'



-- ============================================================
-- 6. Confirm child fact changed
-- ============================================================

SELECT

    shipment_fact_sk,
    shipment_id,
    order_id,

    shipment_status,

    shipped_at,
    delivered_at,

    source_shipment_raw_record_id

FROM warehouse.fact_shipment

WHERE shipment_id = 9103;



-- ============================================================
-- 7. Refresh integrated order
-- ============================================================

\i 'sql/05_etl/013_load_fact_order.sql'



-- ============================================================
-- 8. AFTER
-- ============================================================

SELECT

    order_fact_sk,
    order_id,

    shipment_count,
    delivered_shipment_count,
    in_transit_shipment_count,
    shipped_shipment_count,

    loaded_at

FROM warehouse.fact_order

WHERE order_id = 9999;



-- ============================================================
-- 9. Must remain exactly one order row
-- ============================================================

SELECT

    order_id,

    COUNT(*) AS row_count

FROM warehouse.fact_order

WHERE order_id = 9999

GROUP BY order_id;



-- ============================================================
-- 10. Total integrated order count must remain 3
-- ============================================================

SELECT
    COUNT(*) AS total_order_fact_rows

FROM warehouse.fact_order;