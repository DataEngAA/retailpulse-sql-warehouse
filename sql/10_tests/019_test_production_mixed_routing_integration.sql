-- ============================================================
-- RetailPulse
-- Production integration test:
--
--   NORMAL
--   LATE
--   NORMAL
--
-- Runs the REAL production V2 loader.
--
-- Verifies:
--   - normal rows reach warehouse
--   - late row reaches repair queue
--   - watermark advances across all 3
--   - audit metrics are correct
--   - queue row links to the detecting ETL run
--
-- Finally removes all synthetic data and restores watermark.
-- ============================================================


\set ON_ERROR_STOP on


-- ============================================================
-- 1. Test context
--
-- ON COMMIT PRESERVE ROWS is required because the production
-- loader performs its own COMMITs.
-- ============================================================

DROP TABLE IF EXISTS tmp_019_context;


CREATE TEMP TABLE tmp_019_context (

    test_customer_id BIGINT NOT NULL,

    test_batch_id TEXT NOT NULL,

    watermark_before BIGINT NOT NULL,

    watermark_updated_at_before TIMESTAMPTZ,

    audit_max_before BIGINT NOT NULL,

    base_effective_at TIMESTAMPTZ NOT NULL,

    normal1_version_id BIGINT,

    late_version_id BIGINT,

    normal2_version_id BIGINT,

    max_test_version_id BIGINT,

    test_run_id BIGINT

)
ON COMMIT PRESERVE ROWS;



INSERT INTO tmp_019_context (

    test_customer_id,
    test_batch_id,

    watermark_before,
    watermark_updated_at_before,

    audit_max_before,

    base_effective_at

)

SELECT

    -- Dedicated synthetic customer ID
    900000000000 + w.last_processed_version_id,

    'integration_test_019_'
        || TO_CHAR(
            clock_timestamp(),
            'YYYYMMDD_HH24MISS_US'
        ),

    w.last_processed_version_id,
    w.updated_at,

    COALESCE(
        (
            SELECT MAX(run_id)
            FROM audit.etl_runs
        ),
        0
    ),

    clock_timestamp()

FROM control.pipeline_watermark w

WHERE w.pipeline_name =
      'dim_customer_incremental';



SELECT *
FROM tmp_019_context;



-- ============================================================
-- 2. Safety:
-- test customer must not already exist anywhere
-- ============================================================

CREATE TEMP TABLE tmp_019_fixture_guard (

    violation_count INTEGER NOT NULL,

    CONSTRAINT no_existing_test_customer
        CHECK (violation_count = 0)

)
ON COMMIT PRESERVE ROWS;


INSERT INTO tmp_019_fixture_guard (
    violation_count
)

SELECT

      (
        SELECT COUNT(*)::INTEGER

        FROM warehouse.dim_customer d

        JOIN tmp_019_context c
            ON d.customer_id =
               c.test_customer_id
      )

    + (
        SELECT COUNT(*)::INTEGER

        FROM staging.stg_customer_versions s

        JOIN tmp_019_context c
            ON s.customer_id =
               c.test_customer_id
      )

    + (
        SELECT COUNT(*)::INTEGER

        FROM control.customer_late_arrival_queue q

        JOIN tmp_019_context c
            ON q.customer_id =
               c.test_customer_id
      );



-- ============================================================
-- 3. Safety:
-- customer 101 is used only as a template for attributes.
--
-- Exactly one current row must exist.
-- ============================================================

CREATE TEMP TABLE tmp_019_template_guard (

    violation_count INTEGER NOT NULL,

    CONSTRAINT one_template_customer_required
        CHECK (violation_count = 0)

)
ON COMMIT PRESERVE ROWS;


INSERT INTO tmp_019_template_guard (
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
-- 4. Create isolated warehouse fixture
--
-- This gives the synthetic customer an existing current
-- dimension state so NORMAL/LATE routing can be tested.
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

    c.base_effective_at,
    NULL,
    TRUE,

    -(c.test_customer_id * 10 + 1)

FROM tmp_019_context c

JOIN warehouse.dim_customer d

    ON d.customer_id = 101
   AND d.is_current = TRUE;



-- ============================================================
-- 5. NORMAL version #1
--
-- Future relative to current warehouse valid_from.
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

    'TEST_NORMAL_A',
    d.state,
    d.country,
    d.postal_code,

    d.signup_date,
    d.customer_status,

    c.base_effective_at + INTERVAL '1 hour',
    c.base_effective_at + INTERVAL '1 hour',
    c.base_effective_at + INTERVAL '1 hour',

    'updated_at',
    'integration_test_019',
    c.test_batch_id,
    clock_timestamp()

FROM tmp_019_context c

JOIN warehouse.dim_customer d

    ON d.customer_id =
       c.test_customer_id

   AND d.is_current = TRUE;



-- ============================================================
-- 6. LATE version
--
-- Historical relative to current warehouse valid_from.
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

    'TEST_LATE',
    d.state,
    d.country,
    d.postal_code,

    d.signup_date,
    d.customer_status,

    c.base_effective_at - INTERVAL '1 hour',
    c.base_effective_at - INTERVAL '1 hour',
    c.base_effective_at - INTERVAL '1 hour',

    'updated_at',
    'integration_test_019',
    c.test_batch_id,
    clock_timestamp()

FROM tmp_019_context c

JOIN warehouse.dim_customer d

    ON d.customer_id =
       c.test_customer_id

   AND d.is_current = TRUE;



-- ============================================================
-- 7. NORMAL version #2
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

    -(c.test_customer_id * 10 + 4),

    c.test_customer_id,

    d.first_name,
    d.last_name,
    d.email,
    d.phone,
    d.date_of_birth,

    'TEST_NORMAL_B',
    d.state,
    d.country,
    d.postal_code,

    d.signup_date,
    d.customer_status,

    c.base_effective_at + INTERVAL '2 hours',
    c.base_effective_at + INTERVAL '2 hours',
    c.base_effective_at + INTERVAL '2 hours',

    'updated_at',
    'integration_test_019',
    c.test_batch_id,
    clock_timestamp()

FROM tmp_019_context c

JOIN warehouse.dim_customer d

    ON d.customer_id =
       c.test_customer_id

   AND d.is_current = TRUE;



-- ============================================================
-- 8. Save generated staging IDs
--
-- Never assume they are exactly 72 / 73 / 74.
-- PostgreSQL identity sequences may contain gaps.
-- ============================================================

UPDATE tmp_019_context c

SET

    normal1_version_id =
        s.normal1_version_id,

    late_version_id =
        s.late_version_id,

    normal2_version_id =
        s.normal2_version_id,

    max_test_version_id =
        s.max_test_version_id

FROM (

    SELECT
        batch_id,

        MAX(customer_version_id)
            FILTER (
                WHERE city = 'TEST_NORMAL_A'
            )
            AS normal1_version_id,

        MAX(customer_version_id)
            FILTER (
                WHERE city = 'TEST_LATE'
            )
            AS late_version_id,

        MAX(customer_version_id)
            FILTER (
                WHERE city = 'TEST_NORMAL_B'
            )
            AS normal2_version_id,

        MAX(customer_version_id)
            AS max_test_version_id

    FROM staging.stg_customer_versions

    WHERE source_system =
          'integration_test_019'

    GROUP BY batch_id

) s

WHERE s.batch_id =
      c.test_batch_id;


COMMIT;



-- ============================================================
-- 9. Show actual generated mixed batch
-- ============================================================

SELECT

    s.customer_version_id,
    s.customer_id,
    s.city,
    s.effective_at,

    d.valid_from AS fixture_current_valid_from,

    CASE

        WHEN s.effective_at <= d.valid_from
            THEN 'LATE'

        ELSE 'NORMAL'

    END AS expected_route

FROM staging.stg_customer_versions s

JOIN tmp_019_context c

    ON s.batch_id =
       c.test_batch_id

JOIN warehouse.dim_customer d

    ON d.customer_id =
       c.test_customer_id

   AND d.is_current = TRUE

ORDER BY s.customer_version_id;



-- ============================================================
-- 10. RUN THE REAL PRODUCTION LOADER
-- ============================================================

\i 'sql/05_etl/003_incremental_dim_customer_v2.sql'



-- Production loader resets this to OFF on success.
\set ON_ERROR_STOP on



-- ============================================================
-- 11. Identify the ETL run created by this test
-- ============================================================

UPDATE tmp_019_context c

SET test_run_id = (

    SELECT MAX(e.run_id)

    FROM audit.etl_runs e

    WHERE e.pipeline_name =
          'dim_customer_incremental'

      AND e.run_id >
          c.audit_max_before

);



-- ============================================================
-- 12. Verify ETL audit
-- ============================================================

SELECT

    e.run_id,
    e.status,

    e.watermark_before,
    e.watermark_after,

    e.rows_in_batch,
    e.scd2_rows_inserted,
    e.type1_customers_affected,
    e.late_rows_queued,

    e.error_message

FROM audit.etl_runs e

JOIN tmp_019_context c

    ON e.run_id =
       c.test_run_id;



-- ============================================================
-- 13. Verify LATE row reached V3 queue
-- ============================================================

SELECT

    q.late_arrival_id,

    q.customer_version_id,

    s.city AS staging_city,

    q.customer_id,
    q.effective_at,

    q.status,
    q.repair_action,

    q.detected_run_id

FROM control.customer_late_arrival_queue q

JOIN tmp_019_context c

    ON q.detected_run_id =
       c.test_run_id

JOIN staging.stg_customer_versions s

    ON s.customer_version_id =
       q.customer_version_id

ORDER BY q.customer_version_id;



-- ============================================================
-- 14. Verify warehouse contains ONLY normal path
--
-- Expected:
--
-- TEST_BASE
--      ->
-- TEST_NORMAL_A
--      ->
-- TEST_NORMAL_B current
--
-- TEST_LATE must NOT appear here.
-- ============================================================

SELECT

    d.customer_sk,
    d.customer_id,

    d.city,

    d.valid_from,
    d.valid_to,

    d.is_current,

    d.source_raw_record_id

FROM warehouse.dim_customer d

JOIN tmp_019_context c

    ON d.customer_id =
       c.test_customer_id

ORDER BY d.valid_from;



-- ============================================================
-- 15. Final integration assertions
--
-- Every column should return TRUE.
-- ============================================================

SELECT

    e.status = 'SUCCESS'
        AS audit_success,

    e.watermark_before =
        c.watermark_before
        AS watermark_before_ok,

    e.watermark_after =
        c.max_test_version_id
        AS watermark_after_ok,

    e.rows_in_batch = 3
        AS batch_count_ok,

    e.scd2_rows_inserted = 2
        AS scd2_count_ok,

    e.type1_customers_affected = 1
        AS type1_count_ok,

    e.late_rows_queued = 1
        AS late_count_ok,


    (
        SELECT COUNT(*) = 1

        FROM control.customer_late_arrival_queue q

        WHERE q.detected_run_id =
              c.test_run_id
    )
    AS queue_count_ok,


    (
        SELECT COUNT(*) = 1

        FROM control.customer_late_arrival_queue q

        WHERE q.detected_run_id =
              c.test_run_id

          AND q.customer_version_id =
              c.late_version_id
    )
    AS correct_late_version_queued,


    (
        SELECT COUNT(*) = 3

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id
    )
    AS warehouse_row_count_ok,


    (
        SELECT COUNT(*) = 0

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id

          AND d.city =
              'TEST_LATE'
    )
    AS late_not_in_warehouse,


    (
        SELECT d.city = 'TEST_NORMAL_B'

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id

          AND d.is_current = TRUE
    )
    AS correct_current_state

FROM tmp_019_context c

JOIN audit.etl_runs e

    ON e.run_id =
       c.test_run_id;



-- ============================================================
-- 16. CLEANUP
--
-- Remove every persistent artifact produced by the test.
--
-- Identity/sequence values are intentionally NOT reset.
-- Gaps are normal in PostgreSQL.
-- ============================================================

BEGIN;



-- Queue first because it references audit.etl_runs
DELETE FROM control.customer_late_arrival_queue q

USING tmp_019_context c

WHERE q.customer_version_id IN (

    c.normal1_version_id,
    c.late_version_id,
    c.normal2_version_id

);



-- Remove synthetic warehouse customer/history
DELETE FROM warehouse.dim_customer d

USING tmp_019_context c

WHERE d.customer_id =
      c.test_customer_id;



-- Remove synthetic staging versions
DELETE FROM staging.stg_customer_versions s

USING tmp_019_context c

WHERE s.batch_id =
      c.test_batch_id;



-- Restore production watermark exactly
UPDATE control.pipeline_watermark w

SET
    last_processed_version_id =
        c.watermark_before,

    updated_at =
        c.watermark_updated_at_before

FROM tmp_019_context c

WHERE w.pipeline_name =
      'dim_customer_incremental';



-- Remove synthetic ETL audit run
DELETE FROM audit.etl_runs e

USING tmp_019_context c

WHERE e.run_id =
      c.test_run_id;


COMMIT;



-- ============================================================
-- 17. Verify cleanup
--
-- Every count should be 0 and watermark should equal the
-- original value.
-- ============================================================

SELECT

    c.watermark_before,

    (
        SELECT last_processed_version_id

        FROM control.pipeline_watermark

        WHERE pipeline_name =
              'dim_customer_incremental'
    ) AS watermark_after_cleanup,


    (
        SELECT COUNT(*)

        FROM staging.stg_customer_versions s

        WHERE s.batch_id =
              c.test_batch_id
    ) AS staging_rows_remaining,


    (
        SELECT COUNT(*)

        FROM warehouse.dim_customer d

        WHERE d.customer_id =
              c.test_customer_id
    ) AS warehouse_rows_remaining,


    (
        SELECT COUNT(*)

        FROM control.customer_late_arrival_queue q

        WHERE q.customer_version_id IN (

            c.normal1_version_id,
            c.late_version_id,
            c.normal2_version_id

        )
    ) AS queue_rows_remaining,


    (
        SELECT COUNT(*)

        FROM audit.etl_runs e

        WHERE e.run_id =
              c.test_run_id
    ) AS audit_rows_remaining

FROM tmp_019_context c;



-- ============================================================
-- 18. Clean temporary test state
-- ============================================================

DROP TABLE tmp_019_fixture_guard;
DROP TABLE tmp_019_template_guard;
DROP TABLE tmp_019_context;


\set ON_ERROR_STOP off