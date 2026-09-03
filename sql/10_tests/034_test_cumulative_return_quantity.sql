-- ============================================================
-- TEST 034
-- Cumulative return quantity
--
-- Item 9002 sold quantity = 3
--
-- Existing:
-- 9501 -> qty 1
--
-- New:
-- 9510 -> qty 2
-- 9511 -> qty 1
--
-- cumulative:
-- 1 -> 3 -> 4
--
-- 9511 must be rejected.
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

(
    '9510',
    '9002',
    'REQUESTED',
    '2',
    '0',
    'Cumulative quantity test - valid',
    '2026-09-07 10:00:00+05:30',
    NULL,
    'phase2_demo',
    'return_cumulative_demo_001'
),

(
    '9511',
    '9002',
    'REQUESTED',
    '1',
    '0',
    'Cumulative quantity test - exceeds sold',
    '2026-09-07 11:00:00+05:30',
    NULL,
    'phase2_demo',
    'return_cumulative_demo_001'
);


-- Normal return checks first
\i 'sql/06_quality/010_detect_return_issues.sql'


-- New cumulative check
\i 'sql/06_quality/011_detect_cumulative_return_issues.sql'


SELECT
    r.raw_record_id,
    r.return_id,
    r.order_item_id,
    r.return_quantity,

    q.issue_code,
    q.severity,
    q.action

FROM raw.returns r

LEFT JOIN audit.data_quality_issues q

    ON q.source_schema = 'raw'
   AND q.source_table = 'returns'
   AND q.raw_record_id = r.raw_record_id

WHERE r.batch_id = 'return_cumulative_demo_001'

ORDER BY r.raw_record_id;