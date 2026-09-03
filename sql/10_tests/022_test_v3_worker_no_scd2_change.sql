-- ============================================================
-- RetailPulse
-- V3 Production Worker Integration Test
--
-- Tests actual:
--   NO_SCD2_CHANGE
--
-- Late staging row has the SAME SCD2 state as the
-- historical warehouse interval that already contains it.
--
-- Expected:
--
--   queue -> SUCCESS
--   repair_action -> NO_SCD2_CHANGE
--   warehouse -> completely unchanged
--
-- Everything is cleaned up afterward.
-- ============================================================


\set ON_ERROR_STOP on



-- ============================================================
-- 1. Test context
-- ============================================================

DROP TABLE IF EXISTS tmp_022_context;


CREATE TEMP TABLE tmp_022_context (

    test_customer_id BIGINT NOT NULL,

    test_batch_id TEXT NOT NULL,

    base_from TIMESTAMPTZ NOT NULL,

    late_at TIMESTAMPTZ NOT NULL,

    base_customer_sk BIGINT,

    original_valid_from TIMESTAMPTZ,

    original_valid_to TIMESTAMPTZ,

    original_email TEXT,

    original_source_raw_record_id BIGINT,

    late_version_id BIGINT

)
ON COMMIT PRESERVE ROWS;



WITH test_clock AS (

    SELECT clock_timestamp() AS anchor_time

)

INSERT INTO tmp_022_context (

    test_customer_id,
    test_batch_id,

    base_from,
    late_at

)

SELECT

    940000000000
        + COALESCE(
            (
                SELECT MAX(customer_version_id)
                FROM staging.stg_customer_versions
            ),
            0
        ),

    'integration_test_022_'
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
FROM tmp_022_context;



-- ============================================================
-- 2. Worker safety
--
-- Worker selects oldest PENDING row, therefore isolated test
-- requires no other pending repair.
-- ============================================================

CREATE TEMP TABLE tmp_022_queue_guard (

    violation_count INTEGER NOT NULL,

    CONSTRAINT no_existing_pending_022_repairs
        CHECK (violation_count = 0)

)
ON COMMIT PRESERVE ROWS;


INSERT INTO tmp_022_queue_guard (
    violation_count
)

SELECT COUNT(*)::INTEGER

FROM control.customer_late_arrival_queue

WHERE status = 'PENDING';



-- ============================================================
-- 3. Synthetic customer safety
-- ============================================================

CREATE TEMP TABLE tmp_022_customer_guard (

    violation_count INTEGER NOT NULL,

    CONSTRAINT no_existing_022_customer
        CHECK (violation_count = 0)

)
ON COMMIT PRESERVE ROWS;


INSERT INTO tmp_022_customer_guard (
    violation_count
)

SELECT

      (
        SELECT COUNT(*)::INTEGER

        FROM warehouse.dim_customer d

        JOIN tmp_022_context c
          ON d.customer_id =
             c.test_customer_id
      )

    + (
        SELECT COUNT(*)::INTEGER

        FROM staging.stg_customer_versions s

        JOIN tmp_022_context c
          ON s.customer_id =
             c.test_customer_id
      )

    + (
        SELECT COUNT(*)::INTEGER

        FROM control.customer_late_arrival_queue q

        JOIN tmp_022_context c
          ON q.customer_id =
             c.test_customer_id
      );



-- ============================================================
-- 4. Template customer safety
-- ============================================================

CREATE TEMP TABLE tmp_022_template_guard (

    violation_count INTEGER NOT NULL,

    CONSTRAINT one_022_template_customer
        CHECK (violation_count = 0)

)
ON COMMIT PRESERVE ROWS;


INSERT INTO tmp_022_template_guard (
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
-- 5. Create ONE warehouse interval
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

FROM tmp_022_context c

JOIN warehouse.dim_customer d

  ON d.customer_id = 101
 AND d.is_current = TRUE;



-- ============================================================
-- 6. Create late staging version
--
-- IMPORTANT:
-- SCD2 fields are IDENTICAL to TEST_BASE.
--
-- Type1 email is deliberately stale.
-- Worker must still leave warehouse unchanged.
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

    'historical.old@example.com',

    d.phone,
    d.date_of_birth,

    -- Same SCD2 state as containing warehouse row
    'TEST_BASE',

    d.state,
    d.country,
    d.postal_code,

    d.signup_date,
    d.customer_status,

    c.late_at,
    c.late_at,
    c.late_at,

    'updated_at',
    'integration_test_022',
    c.test_batch_id,
    clock_timestamp()

FROM tmp_022_context c

JOIN warehouse.dim_customer d

  ON d.customer_id =
     c.test_customer_id

 AND d.is_current = TRUE;



-- ============================================================
-- 7. Capture IDs + ORIGINAL warehouse state
-- ============================================================

UPDATE tmp_022_context c

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
-- 8. Queue the late staging row
-- ============================================================

INSERT INTO control.customer_late_arrival_queue (

    customer_version_id,
    customer_id,
    effective_at

)

SELECT

    late_version_id,
    test_customer_id,
    late_at

FROM tmp_022_context;



-- ============================================================
-- 9. Show starting state
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

JOIN tmp_022_context c

  ON d.customer_id =
     c.test_customer_id;



SELECT

    q.late_arrival_id,
    q.customer_version_id,

    q.customer_id,
    q.effective_at,

    q.status

FROM control.customer_late_arrival_queue q

JOIN tmp_022_context c

  ON q.customer_version_id =
     c.late_version_id;



-- ============================================================
-- 10. RUN REAL V3 WORKER
-- ============================================================

\i 'sql/05_etl/006_process_customer_late_arrival_v1.sql'


\set ON_ERROR_STOP on



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

JOIN tmp_022_context c

  ON q.customer_version_id =
     c.late_version_id;



-- ============================================================
-- 12. Verify warehouse after worker
--
-- It should look IDENTICAL.
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

JOIN tmp_022_context c

  ON d.customer_id =
     c.test_customer_id;



-- ============================================================
-- 13. Assertions
--
-- Every result should be TRUE.
-- ============================================================

SELECT


    -- Queue was processed successfully
    (
        SELECT q.status =
               'SUCCESS'

        FROM control.customer_late_arrival_queue q

        WHERE q.customer_version_id =
              c.late_version_id
    )
    AS queue_success,


    -- Correct classification
    (
        SELECT q.repair_action =
               'NO_SCD2_CHANGE'

        FROM control.customer_late_arrival_queue q

        WHERE q.customer_version_id =
              c.late_version_id
    )
    AS action_is_no_scd2_change,


    -- Still exactly one warehouse row
    (
        SELECT COUNT(*) = 1

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id
    )
    AS still_one_history_row,


    -- Same surrogate key
    (
        SELECT d.customer_sk =
               c.base_customer_sk

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id
    )
    AS surrogate_key_unchanged,


    -- Same valid_from
    (
        SELECT d.valid_from =
               c.original_valid_from

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id
    )
    AS valid_from_unchanged,


    -- Still open/current
    (
        SELECT d.valid_to IS NOT DISTINCT FROM
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


    -- Old Type1 email was NOT reintroduced
    (
        SELECT d.email =
               c.original_email

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id
    )
    AS type1_email_unchanged,


    (
        SELECT d.email <>
               'historical.old@example.com'

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id
    )
    AS historical_type1_not_reintroduced,


    -- No SCD2 mutation means source lineage stays untouched too
    (
        SELECT d.source_raw_record_id =
               c.original_source_raw_record_id

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id
    )
    AS source_lineage_unchanged


FROM tmp_022_context c;



-- ============================================================
-- 14. Cleanup
-- ============================================================

BEGIN;


DELETE FROM control.customer_late_arrival_queue q

USING tmp_022_context c

WHERE q.customer_version_id =
      c.late_version_id;


DELETE FROM warehouse.dim_customer d

USING tmp_022_context c

WHERE d.customer_id =
      c.test_customer_id;


DELETE FROM staging.stg_customer_versions s

USING tmp_022_context c

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
              c.late_version_id
    )
    AS queue_rows_remaining

FROM tmp_022_context c;



-- ============================================================
-- 16. Clean TEMP state
-- ============================================================

DROP TABLE tmp_022_queue_guard;
DROP TABLE tmp_022_customer_guard;
DROP TABLE tmp_022_template_guard;
DROP TABLE tmp_022_context;


\set ON_ERROR_STOP off