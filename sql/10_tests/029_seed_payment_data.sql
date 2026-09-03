-- ============================================================
-- TEST 029
-- Seed payment data
--
-- Some rows are valid.
-- Some are intentionally bad.
-- ============================================================


INSERT INTO raw.payments (

    payment_id,
    order_id,

    payment_type,
    payment_status,
    payment_method,

    payment_amount,
    currency,

    payment_created_at,

    transaction_reference,

    source_system,
    batch_id

)

VALUES


-- ============================================================
-- GOOD:
-- first payment attempt failed
-- ============================================================

(
    '8001',
    '5001',

    'PAYMENT',
    'FAILED',
    'CARD',

    '58000',
    'INR',

    '2026-09-01 10:05:00+05:30',

    'TXN-8001',

    'phase2_demo',
    'payment_demo_001'
),


-- ============================================================
-- GOOD:
-- second attempt succeeded
-- ============================================================

(
    '8002',
    '5001',

    'PAYMENT',
    'SUCCESS',
    'CARD',

    '58000',
    'INR',

    '2026-09-01 10:10:00+05:30',

    'TXN-8002',

    'phase2_demo',
    'payment_demo_001'
),


-- ============================================================
-- GOOD:
-- another successful payment
-- ============================================================

(
    '8003',
    '9999',

    'PAYMENT',
    'SUCCESS',
    'UPI',

    '2950',
    'INR',

    '2026-09-02 10:35:00+05:30',

    'TXN-8003',

    'phase2_demo',
    'payment_demo_001'
),


-- ============================================================
-- BAD:
-- missing payment_id
-- ============================================================

(
    NULL,
    '5001',

    'PAYMENT',
    'SUCCESS',
    'CARD',

    '58000',
    'INR',

    '2026-09-01 10:15:00+05:30',

    'TXN-BAD-1',

    'phase2_demo',
    'payment_demo_001'
),


-- ============================================================
-- BAD:
-- invalid order_id
-- ============================================================

(
    '8004',
    'ABC',

    'PAYMENT',
    'SUCCESS',
    'CARD',

    '1000',
    'INR',

    '2026-09-01 11:00:00+05:30',

    'TXN-8004',

    'phase2_demo',
    'payment_demo_001'
),


-- ============================================================
-- BAD:
-- invalid amount
-- ============================================================

(
    '8005',
    '5001',

    'PAYMENT',
    'SUCCESS',
    'CARD',

    'abc',
    'INR',

    '2026-09-01 11:15:00+05:30',

    'TXN-8005',

    'phase2_demo',
    'payment_demo_001'
),


-- ============================================================
-- BAD:
-- negative payment amount
-- ============================================================

(
    '8006',
    '5001',

    'PAYMENT',
    'SUCCESS',
    'CARD',

    '-500',

    'INR',

    '2026-09-01 11:20:00+05:30',

    'TXN-8006',

    'phase2_demo',
    'payment_demo_001'
),


-- ============================================================
-- BAD:
-- invalid timestamp
-- ============================================================

(
    '8007',
    '5001',

    'PAYMENT',
    'SUCCESS',
    'CARD',

    '500',

    'INR',

    'not-a-date',

    'TXN-8007',

    'phase2_demo',
    'payment_demo_001'
),


-- ============================================================
-- INTERESTING:
-- order does not exist yet
--
-- We should probably FLAG this later,
-- not immediately reject it.
-- ============================================================

(
    '8008',
    '7777',

    'PAYMENT',
    'SUCCESS',
    'UPI',

    '1200',
    'INR',

    '2026-09-02 12:00:00+05:30',

    'TXN-8008',

    'phase2_demo',
    'payment_demo_001'
);


-- ============================================================
-- Show payment demo data
-- ============================================================

SELECT

    raw_record_id,

    payment_id,
    order_id,

    payment_type,
    payment_status,
    payment_method,

    payment_amount,
    currency,

    payment_created_at

FROM raw.payments

WHERE batch_id = 'payment_demo_001'

ORDER BY raw_record_id;