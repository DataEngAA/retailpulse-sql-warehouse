-- ============================================================
-- TEST 030
-- Existing payment receives a correction
--
-- Original:
--   payment 8003 = 2950
--
-- Correction:
--   payment 8003 = 3000
--
-- Expected:
--   existing fact updated
--   no duplicate payment
-- ============================================================


-- 1. BEFORE
SELECT
    payment_fact_sk,
    payment_id,
    payment_status,
    payment_amount,
    source_payment_raw_record_id
FROM warehouse.fact_payment
WHERE payment_id = 8003;



-- 2. Simulate corrected source version
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

SELECT

    '8003',
    '9999',

    'PAYMENT',
    'SUCCESS',
    'UPI',

    '3000',
    'INR',

    '2026-09-02 10:35:00+05:30',

    'TXN-8003',

    'phase2_demo',
    'payment_correction_demo_001'

WHERE NOT EXISTS (

    SELECT 1

    FROM raw.payments

    WHERE payment_id = '8003'
      AND batch_id = 'payment_correction_demo_001'

);



-- 3. Quality checks
\i 'sql/06_quality/008_detect_payment_issues.sql'



-- 4. Load corrected version into staging
\i 'sql/03_staging/012_load_stg_payments.sql'



-- 5. Show both staged versions
SELECT
    payment_version_id,
    raw_record_id,
    payment_id,
    payment_amount,
    payment_status,
    batch_id
FROM staging.stg_payments
WHERE payment_id = 8003
ORDER BY payment_version_id;



-- 6. Reload payment fact
\i 'sql/05_etl/010_load_fact_payment.sql'



-- 7. AFTER
SELECT
    payment_fact_sk,
    payment_id,
    payment_status,
    payment_amount,
    source_payment_raw_record_id
FROM warehouse.fact_payment
WHERE payment_id = 8003;



-- 8. Must still be exactly one fact
SELECT
    payment_id,
    COUNT(*) AS row_count
FROM warehouse.fact_payment
WHERE payment_id = 8003
GROUP BY payment_id;



-- 9. Total payment facts must still be 3
SELECT
    COUNT(*) AS total_payment_fact_rows
FROM warehouse.fact_payment;