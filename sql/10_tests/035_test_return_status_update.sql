-- ============================================================
-- TEST 035
-- Return lifecycle update
--
-- 9502:
-- REQUESTED -> COMPLETED
--
-- Expected:
-- same fact row
-- same return_fact_sk
-- completed_at populated
-- no duplicate
-- ============================================================


-- 1. BEFORE
SELECT
    return_fact_sk,
    return_id,
    return_status,
    return_quantity,
    refund_amount,
    requested_at,
    completed_at,
    source_return_raw_record_id
FROM warehouse.fact_return
WHERE return_id = 9502;



-- 2. New source version for the same return
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

SELECT

    '9502',
    '9001',

    'COMPLETED',

    '1',
    '50000',

    'Changed mind',

    '2026-09-05 11:00:00+05:30',
    '2026-09-08 14:00:00+05:30',

    'phase2_demo',
    'return_update_demo_001'

WHERE NOT EXISTS (

    SELECT 1
    FROM raw.returns

    WHERE return_id = '9502'
      AND batch_id = 'return_update_demo_001'
);



-- 3. Normal quality checks
\i 'sql/06_quality/010_detect_return_issues.sql'


-- 4. Cumulative return check
\i 'sql/06_quality/011_detect_cumulative_return_issues.sql'


-- 5. Load new trusted version
\i 'sql/03_staging/016_load_stg_returns.sql'


-- 6. Show staged versions
SELECT
    return_version_id,
    raw_record_id,
    return_id,
    return_status,
    return_quantity,
    refund_amount,
    requested_at,
    completed_at,
    batch_id
FROM staging.stg_returns
WHERE return_id = 9502
ORDER BY return_version_id;



-- 7. Reload return fact
\i 'sql/05_etl/012_load_fact_return.sql'


-- 8. AFTER
SELECT
    return_fact_sk,
    return_id,
    return_status,
    return_quantity,
    refund_amount,
    requested_at,
    completed_at,
    source_return_raw_record_id
FROM warehouse.fact_return
WHERE return_id = 9502;



-- 9. Must still be one row
SELECT
    return_id,
    COUNT(*) AS row_count
FROM warehouse.fact_return
WHERE return_id = 9502
GROUP BY return_id;



-- 10. Total return fact rows should remain 3
SELECT
    COUNT(*) AS total_return_fact_rows
FROM warehouse.fact_return;