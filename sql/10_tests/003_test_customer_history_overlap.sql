BEGIN;

-- Baseline
SELECT
    customer_sk,
    customer_id,
    city,
    valid_from,
    valid_to,
    is_current
FROM warehouse.dim_customer
WHERE customer_id = 200
ORDER BY valid_from;


-- Try to insert a deliberately overlapping historical row.
-- Jaipur is already current from:
-- 2026-08-31 15:00 onward.
--
-- This fake row overlaps Jaipur.

INSERT INTO warehouse.dim_customer (
    customer_id,
    first_name,
    last_name,
    email,

    city,
    customer_status,

    valid_from,
    valid_to,
    is_current,

    source_raw_record_id
)
VALUES (
    200,
    'Priya',
    'Sharma',
    'priya.work@gmail.com',

    'Mumbai',
    'active',

    '2026-09-01 10:00:00+05:30',
    '2026-09-02 10:00:00+05:30',
    FALSE,

    999999
);


ROLLBACK;