-- ============================================================
-- RetailPulse
-- V3 Production Worker Integration Test
--
-- Tests actual:
--   SPLIT_INSERT
--
-- Uses:
--   sql/05_etl/006_process_customer_late_arrival_v1.sql
--
-- Creates isolated warehouse + staging + queue fixtures,
-- runs the REAL worker, verifies result, then cleans up.
-- ============================================================


\set ON_ERROR_STOP on



-- ============================================================
-- 1. Test context
-- ============================================================

DROP TABLE IF EXISTS tmp_020_context;


CREATE TEMP TABLE tmp_020_context (

    test_customer_id BIGINT NOT NULL,

    test_batch_id TEXT NOT NULL,

    base_from TIMESTAMPTZ NOT NULL,

    late_at TIMESTAMPTZ NOT NULL,

    next_from TIMESTAMPTZ NOT NULL,

    base_customer_sk BIGINT,

    next_customer_sk BIGINT,

    split_customer_sk BIGINT,

    late_version_id BIGINT

)
ON COMMIT PRESERVE ROWS;



INSERT INTO tmp_020_context (

    test_customer_id,
    test_batch_id,

    base_from,
    late_at,
    next_from

)

SELECT

    920000000000
        + COALESCE(
            MAX(customer_version_id),
            0
          ),

    'integration_test_020_'
        || TO_CHAR(
            clock_timestamp(),
            'YYYYMMDD_HH24MISS_US'
        ),

    clock_timestamp()
        - INTERVAL '3 days',

    clock_timestamp()
        - INTERVAL '2 days',

    clock_timestamp()
        - INTERVAL '1 day'

FROM staging.stg_customer_versions;



SELECT *
FROM tmp_020_context;



-- ============================================================
-- 2. Safety:
-- worker queue must currently have no PENDING real work
--
-- Otherwise the worker could correctly select an older
-- queue item instead of our test item.
-- ============================================================

CREATE TEMP TABLE tmp_020_queue_guard (

    violation_count INTEGER NOT NULL,

    CONSTRAINT no_existing_pending_repairs
        CHECK (violation_count = 0)

)
ON COMMIT PRESERVE ROWS;


INSERT INTO tmp_020_queue_guard (
    violation_count
)

SELECT COUNT(*)::INTEGER

FROM control.customer_late_arrival_queue

WHERE status = 'PENDING';



-- ============================================================
-- 3. Safety:
-- synthetic customer must not already exist
-- ============================================================

CREATE TEMP TABLE tmp_020_customer_guard (

    violation_count INTEGER NOT NULL,

    CONSTRAINT no_existing_020_customer
        CHECK (violation_count = 0)

)
ON COMMIT PRESERVE ROWS;


INSERT INTO tmp_020_customer_guard (
    violation_count
)

SELECT

      (
        SELECT COUNT(*)::INTEGER

        FROM warehouse.dim_customer d

        JOIN tmp_020_context c
          ON d.customer_id =
             c.test_customer_id
      )

    + (
        SELECT COUNT(*)::INTEGER

        FROM staging.stg_customer_versions s

        JOIN tmp_020_context c
          ON s.customer_id =
             c.test_customer_id
      )

    + (
        SELECT COUNT(*)::INTEGER

        FROM control.customer_late_arrival_queue q

        JOIN tmp_020_context c
          ON q.customer_id =
             c.test_customer_id
      );



-- ============================================================
-- 4. Create isolated warehouse history
--
-- TEST_BASE -> TEST_NEXT
--
-- We copy ordinary Type1 attributes from customer 101.
-- ============================================================

BEGIN;


INSERT INTO warehouse.dim_customer (

    customer_id,

    first_name,
    last_name,
    email,
    phone,
    date_of_birth,
    signup_date,

    city,
    state,
    country,
    postal_code,
    customer_status,

    valid_from,
    valid_to,
    is_current,

    source_raw_record_id

)

SELECT

    c.test_customer_id,

    d.first_name,
    d.last_name,
    d.email,
    d.phone,
    d.date_of_birth,
    d.signup_date,

    'TEST_BASE',
    d.state,
    d.country,
    d.postal_code,
    d.customer_status,

    c.base_from,
    c.next_from,
    FALSE,

    -(c.test_customer_id * 10 + 1)

FROM tmp_020_context c

JOIN warehouse.dim_customer d

  ON d.customer_id = 101
 AND d.is_current = TRUE;



INSERT INTO warehouse.dim_customer (

    customer_id,

    first_name,
    last_name,
    email,
    phone,
    date_of_birth,
    signup_date,

    city,
    state,
    country,
    postal_code,
    customer_status,

    valid_from,
    valid_to,
    is_current,

    source_raw_record_id

)

SELECT

    c.test_customer_id,

    d.first_name,
    d.last_name,
    d.email,
    d.phone,
    d.date_of_birth,
    d.signup_date,

    'TEST_NEXT',
    d.state,
    d.country,
    d.postal_code,
    d.customer_status,

    c.next_from,
    NULL,
    TRUE,

    -(c.test_customer_id * 10 + 2)

FROM tmp_020_context c

JOIN warehouse.dim_customer d

  ON d.customer_id = 101
 AND d.is_current = TRUE;



-- ============================================================
-- 5. Create REAL staging late version
--
-- Deliberately give it an OLD Type1 email.
--
-- V3 should NOT propagate this historical email.
-- The new dimension row should inherit latest Type1 values
-- from the warehouse.
-- ============================================================

INSERT INTO staging.stg_customer_versions (

    raw_record_id,
    customer_id,

    first_name,
    last_name,
    email,
    phone,
    date_of_birth,

    city,
    state,
    country,
    postal_code,

    signup_date,
    customer_status,

    created_at,
    updated_at,
    effective_at,

    timestamp_source,
    source_system,
    batch_id,
    ingested_at

)

SELECT

    -(c.test_customer_id * 10 + 3),

    c.test_customer_id,

    d.first_name,
    d.last_name,

    'historical.old@example.com',

    d.phone,
    d.date_of_birth,

    'TEST_SPLIT',
    d.state,
    d.country,
    d.postal_code,

    d.signup_date,
    d.customer_status,

    c.late_at,
    c.late_at,
    c.late_at,

    'updated_at',
    'integration_test_020',
    c.test_batch_id,
    clock_timestamp()

FROM tmp_020_context c

JOIN warehouse.dim_customer d

  ON d.customer_id =
     c.test_customer_id

 AND d.is_current = TRUE;



-- ============================================================
-- 6. Capture generated staging version + existing SKs
-- ============================================================

UPDATE tmp_020_context c

SET

    late_version_id = (

        SELECT s.customer_version_id

        FROM staging.stg_customer_versions s

        WHERE s.batch_id =
              c.test_batch_id
    ),

    base_customer_sk = (

        SELECT d.customer_sk

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id

          AND d.city =
              'TEST_BASE'
    ),

    next_customer_sk = (

        SELECT d.customer_sk

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id

          AND d.city =
              'TEST_NEXT'
    );


COMMIT;



-- ============================================================
-- 7. Queue the real staging version
-- ============================================================

INSERT INTO control.customer_late_arrival_queue (

    customer_version_id,
    customer_id,
    effective_at

)

SELECT

    c.late_version_id,
    c.test_customer_id,
    c.late_at

FROM tmp_020_context c;



-- ============================================================
-- 8. Show starting state
-- ============================================================

SELECT

    d.customer_sk,
    d.city,
    d.valid_from,
    d.valid_to,
    d.is_current

FROM warehouse.dim_customer d

JOIN tmp_020_context c

  ON d.customer_id =
     c.test_customer_id

ORDER BY d.valid_from;



SELECT

    q.late_arrival_id,
    q.customer_version_id,
    q.customer_id,
    q.effective_at,
    q.status

FROM control.customer_late_arrival_queue q

JOIN tmp_020_context c

  ON q.customer_version_id =
     c.late_version_id;



-- ============================================================
-- 9. RUN REAL V3 WORKER
-- ============================================================

\i 'sql/05_etl/006_process_customer_late_arrival_v1.sql'



-- Worker resets this on success.
\set ON_ERROR_STOP on



-- ============================================================
-- 10. Capture newly generated SPLIT surrogate key
-- ============================================================

UPDATE tmp_020_context c

SET split_customer_sk = (

    SELECT d.customer_sk

    FROM warehouse.dim_customer d

    WHERE d.customer_id =
          c.test_customer_id

      AND d.city =
          'TEST_SPLIT'

);



-- ============================================================
-- 11. Verify queue result
-- ============================================================

SELECT

    q.late_arrival_id,
    q.customer_version_id,

    q.status,
    q.repair_action,

    q.processed_at,
    q.error_message

FROM control.customer_late_arrival_queue q

JOIN tmp_020_context c

  ON q.customer_version_id =
     c.late_version_id;



-- ============================================================
-- 12. Verify repaired warehouse history
-- ============================================================

SELECT

    d.customer_sk,
    d.city,

    d.valid_from,
    d.valid_to,

    d.is_current,

    d.email,

    d.source_raw_record_id

FROM warehouse.dim_customer d

JOIN tmp_020_context c

  ON d.customer_id =
     c.test_customer_id

ORDER BY d.valid_from;



-- ============================================================
-- 13. Assertions
--
-- Every result should be TRUE.
-- ============================================================

SELECT

    (
        SELECT q.status = 'SUCCESS'

        FROM control.customer_late_arrival_queue q

        WHERE q.customer_version_id =
              c.late_version_id
    )
    AS queue_success,


    (
        SELECT q.repair_action =
               'SPLIT_INSERT'

        FROM control.customer_late_arrival_queue q

        WHERE q.customer_version_id =
              c.late_version_id
    )
    AS action_is_split_insert,


    (
        SELECT COUNT(*) = 3

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id
    )
    AS three_history_rows,


    (
        SELECT d.customer_sk =
               c.base_customer_sk

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id

          AND d.city =
              'TEST_BASE'
    )
    AS base_sk_preserved,


    (
        SELECT d.valid_to =
               c.late_at

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id

          AND d.city =
              'TEST_BASE'
    )
    AS base_shortened_correctly,


    (
        SELECT
            d.valid_from = c.late_at

        AND d.valid_to = c.next_from

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id

          AND d.city =
              'TEST_SPLIT'
    )
    AS split_interval_correct,


    (
        SELECT d.customer_sk =
               c.next_customer_sk

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id

          AND d.city =
              'TEST_NEXT'
    )
    AS next_sk_preserved,


    (
        SELECT d.valid_from =
               c.next_from

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id

          AND d.city =
              'TEST_NEXT'
    )
    AS next_boundary_unchanged,


    (
        SELECT d.is_current

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id

          AND d.city =
              'TEST_NEXT'
    )
    AS next_still_current,


    -- --------------------------------------------------------
    -- Historical Type1 value must NOT overwrite warehouse
    -- latest Type1 state.
    -- --------------------------------------------------------

    (
        SELECT d.email <>
               'historical.old@example.com'

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id

          AND d.city =
              'TEST_SPLIT'
    )
    AS historical_type1_not_reintroduced,


    (
        SELECT d.source_raw_record_id =
               s.raw_record_id

        FROM warehouse.dim_customer d

        JOIN staging.stg_customer_versions s

          ON s.customer_version_id =
             c.late_version_id

        WHERE d.customer_id =
              c.test_customer_id

          AND d.city =
              'TEST_SPLIT'
    )
    AS late_source_lineage_preserved


FROM tmp_020_context c;



-- ============================================================
-- 14. Cleanup
-- ============================================================

BEGIN;



DELETE FROM control.customer_late_arrival_queue q

USING tmp_020_context c

WHERE q.customer_version_id =
      c.late_version_id;



DELETE FROM warehouse.dim_customer d

USING tmp_020_context c

WHERE d.customer_id =
      c.test_customer_id;



DELETE FROM staging.stg_customer_versions s

USING tmp_020_context c

WHERE s.batch_id =
      c.test_batch_id;



COMMIT;



-- ============================================================
-- 15. Verify cleanup
-- ============================================================

SELECT

    (
        SELECT COUNT(*)

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id
    ) AS warehouse_rows_remaining,


    (
        SELECT COUNT(*)

        FROM staging.stg_customer_versions s

        WHERE s.batch_id =
              c.test_batch_id
    ) AS staging_rows_remaining,


    (
        SELECT COUNT(*)

        FROM control.customer_late_arrival_queue q

        WHERE q.customer_version_id =
              c.late_version_id
    ) AS queue_rows_remaining

FROM tmp_020_context c;



DROP TABLE tmp_020_queue_guard;
DROP TABLE tmp_020_customer_guard;
DROP TABLE tmp_020_context;


\set ON_ERROR_STOP off