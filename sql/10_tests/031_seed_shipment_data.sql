-- ============================================================
-- TEST 031
-- Shipment demo data
--
-- Mix of valid and intentionally bad records.
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

VALUES


-- GOOD: delivered shipment
(
    '9101',
    '5001',

    'BlueDart',
    'BD-9101',
    'DELIVERED',

    '2026-09-01 18:00:00+05:30',
    '2026-09-03 11:00:00+05:30',

    '100',

    'phase2_demo',
    'shipment_demo_001'
),


-- GOOD: second shipment for same order
(
    '9102',
    '5001',

    'Delhivery',
    'DL-9102',
    'IN_TRANSIT',

    '2026-09-02 09:00:00+05:30',
    NULL,

    '80',

    'phase2_demo',
    'shipment_demo_001'
),


-- GOOD
(
    '9103',
    '9999',

    'BlueDart',
    'BD-9103',
    'SHIPPED',

    '2026-09-02 14:00:00+05:30',
    NULL,

    '50',

    'phase2_demo',
    'shipment_demo_001'
),


-- BAD: missing shipment_id
(
    NULL,
    '5001',

    'BlueDart',
    'BD-BAD-1',
    'SHIPPED',

    '2026-09-02 15:00:00+05:30',
    NULL,

    '100',

    'phase2_demo',
    'shipment_demo_001'
),


-- BAD: invalid order_id
(
    '9104',
    'ABC',

    'BlueDart',
    'BD-9104',
    'SHIPPED',

    '2026-09-02 16:00:00+05:30',
    NULL,

    '100',

    'phase2_demo',
    'shipment_demo_001'
),


-- BAD: invalid shipped timestamp
(
    '9105',
    '5001',

    'BlueDart',
    'BD-9105',
    'SHIPPED',

    'not-a-date',
    NULL,

    '100',

    'phase2_demo',
    'shipment_demo_001'
),


-- BAD: invalid shipping cost
(
    '9106',
    '5001',

    'BlueDart',
    'BD-9106',
    'SHIPPED',

    '2026-09-02 17:00:00+05:30',
    NULL,

    'abc',

    'phase2_demo',
    'shipment_demo_001'
),


-- INTERESTING:
-- valid shipment, but order 7777 does not exist yet
(
    '9107',
    '7777',

    'Delhivery',
    'DL-9107',
    'SHIPPED',

    '2026-09-02 18:00:00+05:30',
    NULL,

    '70',

    'phase2_demo',
    'shipment_demo_001'
);


-- ============================================================
-- Show RAW shipment data
-- ============================================================

SELECT

    raw_record_id,

    shipment_id,
    order_id,

    carrier,
    tracking_number,
    shipment_status,

    shipped_at,
    delivered_at,

    shipping_cost

FROM raw.shipments

WHERE batch_id = 'shipment_demo_001'

ORDER BY raw_record_id;