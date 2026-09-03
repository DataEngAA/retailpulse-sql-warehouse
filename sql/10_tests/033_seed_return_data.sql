-- ============================================================
-- TEST 033
-- Return demo data
--
-- Mix of valid and intentionally bad records.
-- ============================================================


INSERT INTO raw.returns (

    return_id,
    order_item_id,

    return_status,

    return_quantity,

    refund_amount,

    return_reason,

    requested_at,

    completed_at,

    source_system,
    batch_id

)

VALUES


-- GOOD:
-- return 1 unit from order item 9002
(
    '9501',
    '9002',

    'COMPLETED',

    '1',

    '1120',

    'Damaged item',

    '2026-09-05 10:00:00+05:30',

    '2026-09-06 15:00:00+05:30',

    'phase2_demo',
    'return_demo_001'
),


-- GOOD:
-- return request still pending
(
    '9502',
    '9001',

    'REQUESTED',

    '1',

    '0',

    'Changed mind',

    '2026-09-05 11:00:00+05:30',

    NULL,

    'phase2_demo',
    'return_demo_001'
),


-- BAD:
-- missing return_id
(
    NULL,
    '9001',

    'COMPLETED',

    '1',

    '1000',

    'Missing ID test',

    '2026-09-05 12:00:00+05:30',

    '2026-09-06 12:00:00+05:30',

    'phase2_demo',
    'return_demo_001'
),


-- BAD:
-- invalid order_item_id
(
    '9503',
    'ABC',

    'COMPLETED',

    '1',

    '500',

    'Invalid item ID',

    '2026-09-05 13:00:00+05:30',

    '2026-09-06 13:00:00+05:30',

    'phase2_demo',
    'return_demo_001'
),


-- BAD:
-- negative return quantity
(
    '9504',
    '9002',

    'COMPLETED',

    '-1',

    '500',

    'Invalid quantity',

    '2026-09-05 14:00:00+05:30',

    '2026-09-06 14:00:00+05:30',

    'phase2_demo',
    'return_demo_001'
),


-- BAD:
-- return quantity larger than quantity sold
--
-- order item 9001 quantity = 1
-- but trying to return 2
(
    '9505',
    '9001',

    'COMPLETED',

    '2',

    '100000',

    'Too many returned',

    '2026-09-05 15:00:00+05:30',

    '2026-09-06 15:00:00+05:30',

    'phase2_demo',
    'return_demo_001'
),


-- BAD:
-- invalid refund amount
(
    '9506',
    '9002',

    'COMPLETED',

    '1',

    'abc',

    'Bad refund value',

    '2026-09-05 16:00:00+05:30',

    '2026-09-06 16:00:00+05:30',

    'phase2_demo',
    'return_demo_001'
),


-- BAD:
-- invalid timestamp
(
    '9507',
    '9002',

    'COMPLETED',

    '1',

    '500',

    'Bad timestamp',

    'not-a-date',

    NULL,

    'phase2_demo',
    'return_demo_001'
),


-- INTERESTING:
-- order item does not exist yet
--
-- should probably be FLAGGED later
(
    '9508',
    '9999',

    'REQUESTED',

    '1',

    '0',

    'Unknown item for now',

    '2026-09-05 17:00:00+05:30',

    NULL,

    'phase2_demo',
    'return_demo_001'
);


-- ============================================================
-- Show RAW return data
-- ============================================================

SELECT

    raw_record_id,

    return_id,
    order_item_id,

    return_status,

    return_quantity,

    refund_amount,

    return_reason,

    requested_at,
    completed_at

FROM raw.returns

WHERE batch_id = 'return_demo_001'

ORDER BY raw_record_id;