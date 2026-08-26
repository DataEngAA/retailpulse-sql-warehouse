-- ============================================================
-- RetailPulse
-- Incremental Customer Dimension Loader V2
--
-- Supports:
--   - New customers
--   - Type 1 changes
--   - Multiple SCD2 changes/customer/run
--   - SCD2 no-op snapshots
--   - Empty batches
--   - Durable RUNNING audit record
--   - Transactional SUCCESS audit
--
-- Safety:
--   - Late-arriving snapshot guard
--   - Same-time SCD2 conflict guard
--   - Invalid-period guard
--   - Monotonic watermark
--   - Concurrent pipeline protection
--
-- Failed-run behaviour:
--   - RUNNING audit record survives ETL rollback
--   - stale RUNNING records will later be reconciled to FAILED
-- ============================================================


\set ON_ERROR_STOP on


-- ============================================================
-- SESSION CONTEXT
--
-- This TEMP table must survive Transaction A's COMMIT so
-- Transaction B still knows which audit run it belongs to.
-- ============================================================

DROP TABLE IF EXISTS tmp_run_context;


CREATE TEMP TABLE tmp_run_context (

    run_id BIGINT NOT NULL,

    watermark_before BIGINT

)
ON COMMIT PRESERVE ROWS;



-- ============================================================
-- TRANSACTION A
-- Create durable RUNNING audit record
-- ============================================================

BEGIN;


WITH new_run AS (

    INSERT INTO audit.etl_runs (
        pipeline_name,
        status,
        watermark_before
    )

    VALUES (
        'dim_customer_incremental',
        'RUNNING',
        NULL
    )

    RETURNING run_id

)

INSERT INTO tmp_run_context (
    run_id
)

SELECT run_id
FROM new_run;


COMMIT;



-- ============================================================
-- At this point:
--
-- RUNNING audit row is permanently committed.
--
-- If the ETL transaction below fails, this record survives.
-- ============================================================



-- ============================================================
-- TRANSACTION B
-- Actual warehouse ETL
-- ============================================================

BEGIN;



-- ============================================================
-- 1. Lock pipeline watermark and capture starting boundary
-- ============================================================

WITH locked_watermark AS (

    SELECT
        last_processed_version_id

    FROM control.pipeline_watermark

    WHERE pipeline_name = 'dim_customer_incremental'

    FOR UPDATE
)

UPDATE tmp_run_context r

SET
    watermark_before = w.last_processed_version_id

FROM locked_watermark w;



-- ============================================================
-- 2. Capture all unprocessed staging versions
-- ============================================================

CREATE TEMP TABLE tmp_batch
ON COMMIT DROP
AS

SELECT
    s.*,

    ROW_NUMBER() OVER (
        PARTITION BY s.customer_id
        ORDER BY
            s.effective_at,
            s.customer_version_id
    ) AS batch_seq

FROM staging.stg_customer_versions s

WHERE s.customer_version_id >
(
    SELECT watermark_before
    FROM tmp_run_context
);



-- ============================================================
-- 3. Safety guard: late-arriving snapshots
--
-- V2 supports append-only historical processing.
-- Older historical corrections are deferred to V3.
-- ============================================================

CREATE TEMP TABLE tmp_late_arrival_guard (

    violation_count INTEGER NOT NULL,

    CONSTRAINT no_late_arriving_versions
        CHECK (violation_count = 0)

)
ON COMMIT DROP;


INSERT INTO tmp_late_arrival_guard (
    violation_count
)

SELECT COUNT(*)::INTEGER

FROM tmp_batch b

JOIN warehouse.dim_customer d
    ON b.customer_id = d.customer_id
   AND d.is_current = TRUE

WHERE b.effective_at <= d.valid_from;



-- ============================================================
-- 4. Safety guard:
-- conflicting SCD2 states at same business timestamp
-- ============================================================

CREATE TEMP TABLE tmp_same_time_guard (

    violation_count INTEGER NOT NULL,

    CONSTRAINT no_ambiguous_same_time_scd2_versions
        CHECK (violation_count = 0)

)
ON COMMIT DROP;


INSERT INTO tmp_same_time_guard (
    violation_count
)

SELECT COUNT(*)::INTEGER

FROM (

    SELECT
        customer_id,
        effective_at

    FROM (

        SELECT DISTINCT
            customer_id,
            effective_at,
            city,
            state,
            country,
            postal_code,
            customer_status

        FROM tmp_batch

    ) distinct_states

    GROUP BY
        customer_id,
        effective_at

    HAVING COUNT(*) > 1

) conflicts;



-- ============================================================
-- 5. Detect real SCD2 changes
--
-- First incoming version:
--     compare with current warehouse state.
--
-- Later versions:
--     compare with previous version using LAG().
-- ============================================================

CREATE TEMP TABLE tmp_scd2_changes
ON COMMIT DROP
AS

WITH with_predecessors AS (

    SELECT
        b.*,

        d.customer_sk AS warehouse_customer_sk,

        CASE
            WHEN b.batch_seq = 1
                THEN d.city

            ELSE LAG(b.city) OVER (
                PARTITION BY b.customer_id
                ORDER BY b.batch_seq
            )
        END AS prev_city,


        CASE
            WHEN b.batch_seq = 1
                THEN d.state

            ELSE LAG(b.state) OVER (
                PARTITION BY b.customer_id
                ORDER BY b.batch_seq
            )
        END AS prev_state,


        CASE
            WHEN b.batch_seq = 1
                THEN d.country

            ELSE LAG(b.country) OVER (
                PARTITION BY b.customer_id
                ORDER BY b.batch_seq
            )
        END AS prev_country,


        CASE
            WHEN b.batch_seq = 1
                THEN d.postal_code

            ELSE LAG(b.postal_code) OVER (
                PARTITION BY b.customer_id
                ORDER BY b.batch_seq
            )
        END AS prev_postal_code,


        CASE
            WHEN b.batch_seq = 1
                THEN d.customer_status

            ELSE LAG(b.customer_status) OVER (
                PARTITION BY b.customer_id
                ORDER BY b.batch_seq
            )
        END AS prev_customer_status


    FROM tmp_batch b

    LEFT JOIN warehouse.dim_customer d
        ON b.customer_id = d.customer_id
       AND d.is_current = TRUE
),


real_changes AS (

    SELECT *

    FROM with_predecessors

    WHERE

        -- First version of completely new customer
        (
            batch_seq = 1
            AND warehouse_customer_sk IS NULL
        )

        -- Existing customer SCD2 changes
        OR city IS DISTINCT FROM prev_city
        OR state IS DISTINCT FROM prev_state
        OR country IS DISTINCT FROM prev_country
        OR postal_code IS DISTINCT FROM prev_postal_code
        OR customer_status IS DISTINCT FROM prev_customer_status
),


periodized AS (

    SELECT
        *,

        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY
                effective_at,
                customer_version_id
        ) AS change_seq,


        LEAD(effective_at) OVER (
            PARTITION BY customer_id
            ORDER BY
                effective_at,
                customer_version_id
        ) AS next_effective_at

    FROM real_changes
)


SELECT *
FROM periodized;



-- ============================================================
-- 6. Safety guard: invalid / zero-duration periods
-- ============================================================

CREATE TEMP TABLE tmp_invalid_period_guard (

    violation_count INTEGER NOT NULL,

    CONSTRAINT no_invalid_scd2_periods
        CHECK (violation_count = 0)

)
ON COMMIT DROP;


INSERT INTO tmp_invalid_period_guard (
    violation_count
)

SELECT COUNT(*)::INTEGER

FROM tmp_scd2_changes

WHERE next_effective_at IS NOT NULL
  AND next_effective_at <= effective_at;



-- ============================================================
-- 7. Close previous current warehouse row
--
-- Only first real SCD2 change closes the row that was current
-- before this batch.
-- ============================================================

UPDATE warehouse.dim_customer d

SET
    valid_to = c.effective_at,
    is_current = FALSE

FROM tmp_scd2_changes c

WHERE c.change_seq = 1
  AND c.warehouse_customer_sk IS NOT NULL
  AND d.customer_sk = c.warehouse_customer_sk
  AND d.is_current = TRUE;



-- ============================================================
-- 8. Insert entire new SCD2 chain
-- ============================================================

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

    effective_at,
    next_effective_at,
    next_effective_at IS NULL,

    raw_record_id

FROM tmp_scd2_changes

ORDER BY
    customer_id,
    change_seq;



-- ============================================================
-- 9. Latest incoming snapshot/customer for Type 1
--
-- IMPORTANT:
-- use tmp_batch rather than tmp_scd2_changes.
-- Pure Type1 changes must still be processed.
-- ============================================================

CREATE TEMP TABLE tmp_latest_type1
ON COMMIT DROP
AS

SELECT *

FROM (

    SELECT
        b.*,

        ROW_NUMBER() OVER (
            PARTITION BY b.customer_id
            ORDER BY
                b.effective_at DESC,
                b.customer_version_id DESC
        ) AS latest_rank

    FROM tmp_batch b

) ranked

WHERE latest_rank = 1;



-- ============================================================
-- 10. Apply latest Type 1 attributes
-- ============================================================

UPDATE warehouse.dim_customer d

SET
    first_name    = t.first_name,
    last_name     = t.last_name,
    email         = t.email,
    phone         = t.phone,
    date_of_birth = t.date_of_birth,
    signup_date   = t.signup_date

FROM tmp_latest_type1 t

WHERE d.customer_id = t.customer_id;



-- ============================================================
-- 11. Advance watermark
--
-- Empty batch:
--     no update
--
-- Existing watermark:
--     never moves backwards
-- ============================================================

UPDATE control.pipeline_watermark w

SET
    last_processed_version_id = x.max_version_id,

    updated_at = clock_timestamp()

FROM (

    SELECT
        MAX(customer_version_id) AS max_version_id

    FROM tmp_batch

) x

WHERE w.pipeline_name = 'dim_customer_incremental'

  AND x.max_version_id IS NOT NULL

  AND x.max_version_id >
      w.last_processed_version_id;



-- ============================================================
-- 12. Mark durable audit record SUCCESS
--
-- This happens INSIDE the same transaction as:
--
-- warehouse changes
-- watermark changes
--
-- Therefore they commit atomically.
-- ============================================================

UPDATE audit.etl_runs e

SET
    finished_at = clock_timestamp(),

    status = 'SUCCESS',

    watermark_before = r.watermark_before,

    watermark_after =
        w.last_processed_version_id,

    rows_in_batch = (
        SELECT COUNT(*)::INTEGER
        FROM tmp_batch
    ),

    scd2_rows_inserted = (
        SELECT COUNT(*)::INTEGER
        FROM tmp_scd2_changes
    ),

    type1_customers_affected = (
        SELECT COUNT(*)::INTEGER
        FROM tmp_latest_type1
    ),

    error_message = NULL


FROM tmp_run_context r

JOIN control.pipeline_watermark w
    ON w.pipeline_name =
       'dim_customer_incremental'

WHERE e.run_id = r.run_id;



-- ============================================================
-- 13. Commit warehouse + watermark + SUCCESS audit
-- ============================================================

COMMIT;



-- ============================================================
-- 14. Display persisted run result
-- ============================================================

SELECT
    e.run_id,
    e.pipeline_name,
    e.status,

    e.started_at,
    e.finished_at,

    e.watermark_before,
    e.watermark_after,

    e.rows_in_batch,
    e.scd2_rows_inserted,
    e.type1_customers_affected,

    e.error_message

FROM audit.etl_runs e

JOIN tmp_run_context r
    ON e.run_id = r.run_id;



-- ============================================================
-- 15. Clean session context after successful run
-- ============================================================

DROP TABLE tmp_run_context;


\set ON_ERROR_STOP off