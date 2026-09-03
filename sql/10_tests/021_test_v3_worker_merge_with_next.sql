-- ============================================================
-- RetailPulse
-- V3 Production Worker Integration Test
--
-- Tests actual:
--   MERGE_WITH_NEXT
--
-- Scenario:
--
--   TEST_BASE
--       ↓
--   TEST_NEXT
--
-- Late staging version says TEST_NEXT started earlier.
--
-- Expected:
--
--   shorten TEST_BASE
--   move existing TEST_NEXT.valid_from backward
--   preserve TEST_NEXT surrogate key
--   DO NOT insert another TEST_NEXT row
--
-- Everything is cleaned up afterward.
-- ============================================================


\set ON_ERROR_STOP on



-- ============================================================
-- 1. Test context
-- ============================================================

DROP TABLE IF EXISTS tmp_021_context;


CREATE TEMP TABLE tmp_021_context (

    test_customer_id BIGINT NOT NULL,

    test_batch_id TEXT NOT NULL,

    base_from TIMESTAMPTZ NOT NULL,

    late_at TIMESTAMPTZ NOT NULL,

    next_from TIMESTAMPTZ NOT NULL,

    base_customer_sk BIGINT,

    next_customer_sk BIGINT,

    late_version_id BIGINT

)
ON COMMIT PRESERVE ROWS;



WITH test_clock AS (

    SELECT clock_timestamp() AS anchor_time

)

INSERT INTO tmp_021_context (

    test_customer_id,
    test_batch_id,

    base_from,
    late_at,
    next_from

)

SELECT

    930000000000
        + COALESCE(
            (
                SELECT MAX(customer_version_id)
                FROM staging.stg_customer_versions
            ),
            0
        ),

    'integration_test_021_'
        || TO_CHAR(
            t.anchor_time,
            'YYYYMMDD_HH24MISS_US'
        ),

    t.anchor_time
        - INTERVAL '3 days',

    t.anchor_time
        - INTERVAL '2 days',

    t.anchor_time
        - INTERVAL '1 day'

FROM test_clock t;



SELECT *
FROM tmp_021_context;



-- ============================================================
-- 2. Worker safety
--
-- V3 worker processes the oldest PENDING queue row.
-- For this isolated integration test there must be no other
-- PENDING work.
-- ============================================================

CREATE TEMP TABLE tmp_021_queue_guard (

    violation_count INTEGER NOT NULL,

    CONSTRAINT no_existing_pending_021_repairs
        CHECK (violation_count = 0)

)
ON COMMIT PRESERVE ROWS;


INSERT INTO tmp_021_queue_guard (
    violation_count
)

SELECT COUNT(*)::INTEGER

FROM control.customer_late_arrival_queue

WHERE status = 'PENDING';



-- ============================================================
-- 3. Synthetic customer must not already exist
-- ============================================================

CREATE TEMP TABLE tmp_021_customer_guard (

    violation_count INTEGER NOT NULL,

    CONSTRAINT no_existing_021_customer
        CHECK (violation_count = 0)

)
ON COMMIT PRESERVE ROWS;


INSERT INTO tmp_021_customer_guard (
    violation_count
)

SELECT

      (
        SELECT COUNT(*)::INTEGER

        FROM warehouse.dim_customer d

        JOIN tmp_021_context c
          ON d.customer_id =
             c.test_customer_id
      )

    + (
        SELECT COUNT(*)::INTEGER

        FROM staging.stg_customer_versions s

        JOIN tmp_021_context c
          ON s.customer_id =
             c.test_customer_id
      )

    + (
        SELECT COUNT(*)::INTEGER

        FROM control.customer_late_arrival_queue q

        JOIN tmp_021_context c
          ON q.customer_id =
             c.test_customer_id
      );



-- ============================================================
-- 4. Template customer safety
-- ============================================================

CREATE TEMP TABLE tmp_021_template_guard (

    violation_count INTEGER NOT NULL,

    CONSTRAINT one_021_template_customer
        CHECK (violation_count = 0)

)
ON COMMIT PRESERVE ROWS;


INSERT INTO tmp_021_template_guard (
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
-- 5. Build existing warehouse history
--
-- TEST_BASE
-- base_from -> next_from
--
-- TEST_NEXT
-- next_from -> current
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

FROM tmp_021_context c

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

FROM tmp_021_context c

JOIN warehouse.dim_customer d

  ON d.customer_id = 101
 AND d.is_current = TRUE;



-- ============================================================
-- 6. Create late staging version
--
-- SCD2 state deliberately equals TEST_NEXT.
--
-- But its effective_at is EARLIER than TEST_NEXT.valid_from.
--
-- This should become MERGE_WITH_NEXT.
--
-- We again use a deliberately stale Type1 email to prove V3
-- doesn't resurrect it.
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

    -- Same SCD2 state as immediately next warehouse interval
     'TEST_NEXT',

    d.state,
    d.country,
    d.postal_code,

    d.signup_date,
    d.customer_status,

    c.late_at,
    c.late_at,
    c.late_at,

    'updated_at',
    'integration_test_021',
    c.test_batch_id,
    clock_timestamp()

FROM tmp_021_context c

JOIN warehouse.dim_customer d

  ON d.customer_id =
     c.test_customer_id

 AND d.is_current = TRUE;



-- ============================================================
-- 7. Capture generated IDs / existing surrogate keys
-- ============================================================

UPDATE tmp_021_context c

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
-- 8. Queue late version
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

FROM tmp_021_context;



-- ============================================================
-- 9. Show starting warehouse history
-- ============================================================

SELECT

    d.customer_sk,
    d.city,

    d.valid_from,
    d.valid_to,

    d.is_current

FROM warehouse.dim_customer d

JOIN tmp_021_context c

  ON d.customer_id =
     c.test_customer_id

ORDER BY d.valid_from;



-- ============================================================
-- 10. Show queued repair
-- ============================================================

SELECT

    q.late_arrival_id,
    q.customer_version_id,

    q.customer_id,
    q.effective_at,

    q.status

FROM control.customer_late_arrival_queue q

JOIN tmp_021_context c

  ON q.customer_version_id =
     c.late_version_id;



-- ============================================================
-- 11. RUN REAL V3 WORKER
-- ============================================================

\i 'sql/05_etl/006_process_customer_late_arrival_v1.sql'



-- Worker turns it OFF after successful execution.
\set ON_ERROR_STOP on



-- ============================================================
-- 12. Verify queue result
-- ============================================================

SELECT

    q.late_arrival_id,
    q.customer_version_id,

    q.status,
    q.repair_action,

    q.processed_at,
    q.error_message

FROM control.customer_late_arrival_queue q

JOIN tmp_021_context c

  ON q.customer_version_id =
     c.late_version_id;



-- ============================================================
-- 13. Verify repaired warehouse
--
-- Expected only TWO rows:
--
-- TEST_BASE
-- base_from -> late_at
--
-- TEST_NEXT
-- late_at -> current
--
-- No new TEST_NEXT row should exist.
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

JOIN tmp_021_context c

  ON d.customer_id =
     c.test_customer_id

ORDER BY d.valid_from;



-- ============================================================
-- 14. Assertions
--
-- Every result should be TRUE.
-- ============================================================

SELECT


    -- --------------------------------------------------------
    -- Queue outcome
    -- --------------------------------------------------------

    (
        SELECT q.status =
               'SUCCESS'

        FROM control.customer_late_arrival_queue q

        WHERE q.customer_version_id =
              c.late_version_id
    )
    AS queue_success,


    (
        SELECT q.repair_action =
               'MERGE_WITH_NEXT'

        FROM control.customer_late_arrival_queue q

        WHERE q.customer_version_id =
              c.late_version_id
    )
    AS action_is_merge_with_next,


    -- --------------------------------------------------------
    -- No extra dimension row was inserted
    -- --------------------------------------------------------

    (
        SELECT COUNT(*) = 2

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id
    )
    AS exactly_two_history_rows,


    -- --------------------------------------------------------
    -- Existing TEST_BASE surrogate key preserved
    -- --------------------------------------------------------

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


    -- --------------------------------------------------------
    -- Base interval shortened correctly
    -- --------------------------------------------------------

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


    -- --------------------------------------------------------
    -- Existing next surrogate key preserved
    -- --------------------------------------------------------

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


    -- --------------------------------------------------------
    -- Existing next interval moved backward
    -- --------------------------------------------------------

    (
        SELECT d.valid_from =
               c.late_at

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id

          AND d.city =
              'TEST_NEXT'
    )
    AS next_moved_backward,


    -- --------------------------------------------------------
    -- TEST_NEXT remains current
    -- --------------------------------------------------------

    (
        SELECT d.valid_to IS NULL
           AND d.is_current

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id

          AND d.city =
              'TEST_NEXT'
    )
    AS next_still_current,


    -- --------------------------------------------------------
    -- There must only be one TEST_NEXT row
    -- --------------------------------------------------------

    (
        SELECT COUNT(*) = 1

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id

          AND d.city =
              'TEST_NEXT'
    )
    AS no_duplicate_next_state,


    -- --------------------------------------------------------
    -- Historical Type1 email must NOT overwrite latest
    -- warehouse Type1 state.
    -- --------------------------------------------------------

    (
        SELECT d.email <>
               'historical.old@example.com'

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id

          AND d.city =
              'TEST_NEXT'
    )
    AS historical_type1_not_reintroduced,


    -- --------------------------------------------------------
    -- Existing TEST_NEXT row now records the late source
    -- that established its earlier business-time boundary.
    -- --------------------------------------------------------

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
              'TEST_NEXT'
    )
    AS late_source_lineage_applied


FROM tmp_021_context c;



-- ============================================================
-- 15. Cleanup
-- ============================================================

BEGIN;



DELETE FROM control.customer_late_arrival_queue q

USING tmp_021_context c

WHERE q.customer_version_id =
      c.late_version_id;



DELETE FROM warehouse.dim_customer d

USING tmp_021_context c

WHERE d.customer_id =
      c.test_customer_id;



DELETE FROM staging.stg_customer_versions s

USING tmp_021_context c

WHERE s.batch_id =
      c.test_batch_id;



COMMIT;



-- ============================================================
-- 16. Verify cleanup
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

FROM tmp_021_context c;



-- ============================================================
-- 17. Clean TEMP state
-- ============================================================

DROP TABLE tmp_021_queue_guard;
DROP TABLE tmp_021_customer_guard;
DROP TABLE tmp_021_template_guard;
DROP TABLE tmp_021_context;


\set ON_ERROR_STOP off