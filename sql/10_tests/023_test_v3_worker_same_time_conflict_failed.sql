-- ============================================================
-- RetailPulse
-- V3 Production Worker Integration Test
--
-- Tests recognised FAILED path:
--   conflicting SCD2 states at the same business timestamp
--
-- Expected:
--
--   queue status      -> FAILED
--   repair_action     -> NULL
--   error_message     -> conflict explanation
--   warehouse history -> completely unchanged
--
-- Everything is cleaned up afterward.
-- ============================================================


\set ON_ERROR_STOP on



-- ============================================================
-- 1. Test context
-- ============================================================

DROP TABLE IF EXISTS tmp_023_context;


CREATE TEMP TABLE tmp_023_context (

    test_customer_id BIGINT NOT NULL,

    test_batch_id TEXT NOT NULL,

    base_from TIMESTAMPTZ NOT NULL,

    late_at TIMESTAMPTZ NOT NULL,

    base_customer_sk BIGINT,

    original_valid_from TIMESTAMPTZ,

    original_valid_to TIMESTAMPTZ,

    original_email TEXT,

    original_source_raw_record_id BIGINT,

    queued_version_id BIGINT,

    conflicting_version_id BIGINT

)
ON COMMIT PRESERVE ROWS;



WITH test_clock AS (

    SELECT clock_timestamp() AS anchor_time

)

INSERT INTO tmp_023_context (

    test_customer_id,
    test_batch_id,

    base_from,
    late_at

)

SELECT

    950000000000
        + COALESCE(
            (
                SELECT MAX(customer_version_id)
                FROM staging.stg_customer_versions
            ),
            0
        ),

    'integration_test_023_'
        || TO_CHAR(
            t.anchor_time,
            'YYYYMMDD_HH24MISS_US'
        ),

    t.anchor_time
        - INTERVAL '3 days',

    t.anchor_time
        - INTERVAL '2 days'

FROM test_clock t;



SELECT *
FROM tmp_023_context;



-- ============================================================
-- 2. Worker safety:
-- no unrelated PENDING queue work
-- ============================================================

CREATE TEMP TABLE tmp_023_queue_guard (

    violation_count INTEGER NOT NULL,

    CONSTRAINT no_existing_pending_023_repairs
        CHECK (violation_count = 0)

)
ON COMMIT PRESERVE ROWS;


INSERT INTO tmp_023_queue_guard (
    violation_count
)

SELECT COUNT(*)::INTEGER

FROM control.customer_late_arrival_queue

WHERE status = 'PENDING';



-- ============================================================
-- 3. Synthetic customer safety
-- ============================================================

CREATE TEMP TABLE tmp_023_customer_guard (

    violation_count INTEGER NOT NULL,

    CONSTRAINT no_existing_023_customer
        CHECK (violation_count = 0)

)
ON COMMIT PRESERVE ROWS;


INSERT INTO tmp_023_customer_guard (
    violation_count
)

SELECT

      (
        SELECT COUNT(*)::INTEGER

        FROM warehouse.dim_customer d

        JOIN tmp_023_context c
          ON d.customer_id =
             c.test_customer_id
      )

    + (
        SELECT COUNT(*)::INTEGER

        FROM staging.stg_customer_versions s

        JOIN tmp_023_context c
          ON s.customer_id =
             c.test_customer_id
      )

    + (
        SELECT COUNT(*)::INTEGER

        FROM control.customer_late_arrival_queue q

        JOIN tmp_023_context c
          ON q.customer_id =
             c.test_customer_id
      );



-- ============================================================
-- 4. Template customer safety
-- ============================================================

CREATE TEMP TABLE tmp_023_template_guard (

    violation_count INTEGER NOT NULL,

    CONSTRAINT one_023_template_customer
        CHECK (violation_count = 0)

)
ON COMMIT PRESERVE ROWS;


INSERT INTO tmp_023_template_guard (
    violation_count
)

SELECT

    CASE
        WHEN COUNT(*) = 1
            THEN 0
        ELSE 1
    END

FROM warehouse.dim_customer

WHERE customer_id = 101
  AND is_current = TRUE;



-- ============================================================
-- 5. Create one existing warehouse interval
--
-- TEST_BASE
-- base_from -> current
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
    NULL,
    TRUE,

    -(c.test_customer_id * 10 + 1)

FROM tmp_023_context c

JOIN warehouse.dim_customer d

  ON d.customer_id = 101
 AND d.is_current = TRUE;



-- ============================================================
-- 6. Create first staging state
--
-- This is the version we will queue for repair.
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

    -(c.test_customer_id * 10 + 2),

    c.test_customer_id,

    d.first_name,
    d.last_name,
    d.email,
    d.phone,
    d.date_of_birth,

    'TEST_CONFLICT_A',

    d.state,
    d.country,
    d.postal_code,

    d.signup_date,
    d.customer_status,

    c.late_at,
    c.late_at,
    c.late_at,

    'updated_at',
    'integration_test_023',
    c.test_batch_id,
    clock_timestamp()

FROM tmp_023_context c

JOIN warehouse.dim_customer d

  ON d.customer_id =
     c.test_customer_id

 AND d.is_current = TRUE;



-- ============================================================
-- 7. Create SECOND staging state
--
-- Same customer
-- Same effective_at
-- DIFFERENT SCD2 city
--
-- This creates business-time ambiguity.
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
    d.email,
    d.phone,
    d.date_of_birth,

    'TEST_CONFLICT_B',

    d.state,
    d.country,
    d.postal_code,

    d.signup_date,
    d.customer_status,

    c.late_at,
    c.late_at,
    c.late_at,

    'updated_at',
    'integration_test_023',
    c.test_batch_id,
    clock_timestamp()

FROM tmp_023_context c

JOIN warehouse.dim_customer d

  ON d.customer_id =
     c.test_customer_id

 AND d.is_current = TRUE;



-- ============================================================
-- 8. Capture IDs + original warehouse state
-- ============================================================

UPDATE tmp_023_context c

SET

    queued_version_id = (

        SELECT s.customer_version_id

        FROM staging.stg_customer_versions s

        WHERE s.batch_id =
              c.test_batch_id

          AND s.city =
              'TEST_CONFLICT_A'
    ),


    conflicting_version_id = (

        SELECT s.customer_version_id

        FROM staging.stg_customer_versions s

        WHERE s.batch_id =
              c.test_batch_id

          AND s.city =
              'TEST_CONFLICT_B'
    ),


    base_customer_sk = (

        SELECT d.customer_sk

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id
    ),


    original_valid_from = (

        SELECT d.valid_from

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id
    ),


    original_valid_to = (

        SELECT d.valid_to

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id
    ),


    original_email = (

        SELECT d.email

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id
    ),


    original_source_raw_record_id = (

        SELECT d.source_raw_record_id

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id
    );


COMMIT;



-- ============================================================
-- 9. Show the ambiguity
-- ============================================================

SELECT

    s.customer_version_id,
    s.customer_id,
    s.city,
    s.effective_at

FROM staging.stg_customer_versions s

JOIN tmp_023_context c

  ON s.batch_id =
     c.test_batch_id

ORDER BY s.customer_version_id;



-- ============================================================
-- 10. Queue ONLY conflict A
--
-- Worker must still discover conflict B from staging.
-- ============================================================

INSERT INTO control.customer_late_arrival_queue (

    customer_version_id,
    customer_id,
    effective_at

)

SELECT

    queued_version_id,
    test_customer_id,
    late_at

FROM tmp_023_context;



-- ============================================================
-- 11. Show queue before worker
-- ============================================================

SELECT

    q.late_arrival_id,
    q.customer_version_id,

    q.customer_id,
    q.effective_at,

    q.status,
    q.repair_action

FROM control.customer_late_arrival_queue q

JOIN tmp_023_context c

  ON q.customer_version_id =
     c.queued_version_id;



-- ============================================================
-- 12. RUN REAL V3 WORKER
-- ============================================================

\i 'sql/05_etl/006_process_customer_late_arrival_v1.sql'


\set ON_ERROR_STOP on



-- ============================================================
-- 13. Verify queue FAILED
-- ============================================================

SELECT

    q.late_arrival_id,
    q.customer_version_id,

    q.status,
    q.repair_action,

    q.processed_at,
    q.error_message

FROM control.customer_late_arrival_queue q

JOIN tmp_023_context c

  ON q.customer_version_id =
     c.queued_version_id;



-- ============================================================
-- 14. Verify warehouse remained unchanged
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

JOIN tmp_023_context c

  ON d.customer_id =
     c.test_customer_id;



-- ============================================================
-- 15. Assertions
--
-- Every result should be TRUE.
-- ============================================================

SELECT


    (
        SELECT q.status =
               'FAILED'

        FROM control.customer_late_arrival_queue q

        WHERE q.customer_version_id =
              c.queued_version_id
    )
    AS queue_failed,


    (
        SELECT q.repair_action IS NULL

        FROM control.customer_late_arrival_queue q

        WHERE q.customer_version_id =
              c.queued_version_id
    )
    AS no_repair_action,


    (
        SELECT q.processed_at IS NOT NULL

        FROM control.customer_late_arrival_queue q

        WHERE q.customer_version_id =
              c.queued_version_id
    )
    AS processed_at_recorded,


    (
        SELECT q.error_message =
               'Conflicting SCD2 states exist at the same business timestamp.'

        FROM control.customer_late_arrival_queue q

        WHERE q.customer_version_id =
              c.queued_version_id
    )
    AS correct_error_message,


    (
        SELECT COUNT(*) = 1

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id
    )
    AS still_one_history_row,


    (
        SELECT d.customer_sk =
               c.base_customer_sk

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id
    )
    AS surrogate_key_unchanged,


    (
        SELECT d.city =
               'TEST_BASE'

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id
    )
    AS city_unchanged,


    (
        SELECT d.valid_from =
               c.original_valid_from

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id
    )
    AS valid_from_unchanged,


    (
        SELECT d.valid_to
               IS NOT DISTINCT FROM
               c.original_valid_to

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id
    )
    AS valid_to_unchanged,


    (
        SELECT d.is_current

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id
    )
    AS still_current,


    (
        SELECT d.email =
               c.original_email

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id
    )
    AS email_unchanged,


    (
        SELECT d.source_raw_record_id =
               c.original_source_raw_record_id

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id
    )
    AS source_lineage_unchanged


FROM tmp_023_context c;



-- ============================================================
-- 16. Cleanup
-- ============================================================

BEGIN;


DELETE FROM control.customer_late_arrival_queue q

USING tmp_023_context c

WHERE q.customer_version_id =
      c.queued_version_id;


DELETE FROM staging.stg_customer_versions s

USING tmp_023_context c

WHERE s.batch_id =
      c.test_batch_id;


DELETE FROM warehouse.dim_customer d

USING tmp_023_context c

WHERE d.customer_id =
      c.test_customer_id;


COMMIT;



-- ============================================================
-- 17. Verify cleanup
-- ============================================================

SELECT

    (
        SELECT COUNT(*)

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id
    )
    AS warehouse_rows_remaining,


    (
        SELECT COUNT(*)

        FROM staging.stg_customer_versions s

        WHERE s.batch_id =
              c.test_batch_id
    )
    AS staging_rows_remaining,


    (
        SELECT COUNT(*)

        FROM control.customer_late_arrival_queue q

        WHERE q.customer_version_id =
              c.queued_version_id
    )
    AS queue_rows_remaining

FROM tmp_023_context c;



-- ============================================================
-- 18. Clean TEMP state
-- ============================================================

DROP TABLE tmp_023_queue_guard;
DROP TABLE tmp_023_customer_guard;
DROP TABLE tmp_023_template_guard;
DROP TABLE tmp_023_context;


\set ON_ERROR_STOP off