-- ============================================================
-- RetailPulse
-- Incremental Customer Dimension Loader V2
--
-- Features:
--   - New customers
--   - Type 1 updates
--   - Multiple SCD2 changes/customer/run
--   - SCD2 no-op snapshots
--   - Empty batches
--   - Durable RUNNING audit
--   - Late-arrival routing to V3 repair queue
--   - Atomic warehouse + queue + watermark + SUCCESS audit
--
-- Late-arrival strategy:
--
--   NORMAL -> process through V2
--   LATE   -> control.customer_late_arrival_queue
--
-- A late row no longer blocks the normal watermark.
-- ============================================================


\set ON_ERROR_STOP on



-- ============================================================
-- SESSION CONTEXT
--
-- Must survive Transaction A COMMIT so Transaction B knows
-- which audit run it belongs to.
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
-- TRANSACTION B
--
-- Everything below is one atomic ETL transaction:
--
--   routing
--   queue handoff
--   warehouse changes
--   watermark advancement
--   SUCCESS audit
--
-- If anything fails, all of these roll back together.
-- ============================================================

BEGIN;



-- ============================================================
-- 1. Lock watermark
-- ============================================================

WITH locked_watermark AS (

    SELECT
        last_processed_version_id

    FROM control.pipeline_watermark

    WHERE pipeline_name =
          'dim_customer_incremental'

    FOR UPDATE
)

UPDATE tmp_run_context r

SET
    watermark_before =
        w.last_processed_version_id

FROM locked_watermark w;



-- ============================================================
-- 2. Guard: pipeline watermark must exist
-- ============================================================

CREATE TEMP TABLE tmp_watermark_guard (

    violation_count INTEGER NOT NULL,

    CONSTRAINT customer_watermark_must_exist
        CHECK (violation_count = 0)

)
ON COMMIT DROP;


INSERT INTO tmp_watermark_guard (
    violation_count
)

SELECT

    CASE
        WHEN watermark_before IS NULL
            THEN 1
        ELSE 0
    END

FROM tmp_run_context;



-- ============================================================
-- 3. Capture ALL unprocessed staging rows
--
-- IMPORTANT:
-- This includes both NORMAL and LATE rows.
--
-- The final watermark is based on THIS table.
-- ============================================================

CREATE TEMP TABLE tmp_all_batch
ON COMMIT DROP
AS

SELECT
    s.*

FROM staging.stg_customer_versions s

WHERE s.customer_version_id >
(
    SELECT watermark_before
    FROM tmp_run_context
);



-- ============================================================
-- 4. Classify each staging version
--
-- Rules:
--
-- New customer:
--     NORMAL
--
-- Existing customer:
--     effective_at <= current.valid_from
--         -> LATE
--
--     effective_at > current.valid_from
--         -> NORMAL
--
-- The <= boundary is intentionally conservative.
-- ============================================================

CREATE TEMP TABLE tmp_routed_batch
ON COMMIT DROP
AS

SELECT
    b.*,

    CASE

        WHEN d.customer_sk IS NULL
            THEN 'NORMAL'

        WHEN b.effective_at <= d.valid_from
            THEN 'LATE'

        ELSE 'NORMAL'

    END AS route

FROM tmp_all_batch b

LEFT JOIN warehouse.dim_customer d

    ON d.customer_id = b.customer_id
   AND d.is_current = TRUE;



-- ============================================================
-- 5. Capture LATE versions
-- ============================================================

CREATE TEMP TABLE tmp_late_batch
ON COMMIT DROP
AS

SELECT *

FROM tmp_routed_batch

WHERE route = 'LATE';



-- ============================================================
-- 6. Hand LATE versions to V3 repair queue
--
-- customer_version_id is the idempotency key.
--
-- Queue insert occurs in the SAME transaction as the
-- watermark advancement.
-- ============================================================

INSERT INTO control.customer_late_arrival_queue (

    customer_version_id,
    customer_id,
    effective_at,
    detected_run_id

)

SELECT
    l.customer_version_id,
    l.customer_id,
    l.effective_at,

    r.run_id

FROM tmp_late_batch l

CROSS JOIN tmp_run_context r

ON CONFLICT (customer_version_id)
DO NOTHING;



-- ============================================================
-- 7. Build NORMAL V2 working batch
--
-- Late versions are now excluded from normal SCD processing.
-- ============================================================

CREATE TEMP TABLE tmp_batch
ON COMMIT DROP
AS

SELECT
    r.*,

    ROW_NUMBER() OVER (

        PARTITION BY r.customer_id

        ORDER BY
            r.effective_at,
            r.customer_version_id

    ) AS batch_seq

FROM tmp_routed_batch r

WHERE r.route = 'NORMAL';



-- ============================================================
-- 8. Safety guard:
-- conflicting NORMAL SCD2 states at same business timestamp
--
-- Late versions are handled separately by V3.
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

SELECT
    COUNT(*)::INTEGER

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
-- 9. Detect real SCD2 changes in NORMAL batch
--
-- First NORMAL version:
--     compare against current warehouse state
--
-- Later NORMAL versions:
--     compare against previous NORMAL batch version
-- ============================================================

CREATE TEMP TABLE tmp_scd2_changes
ON COMMIT DROP
AS

WITH with_predecessors AS (

    SELECT
        b.*,

        d.customer_sk
            AS warehouse_customer_sk,


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

        ON d.customer_id = b.customer_id
       AND d.is_current = TRUE
),


real_changes AS (

    SELECT *

    FROM with_predecessors

    WHERE

        -- First ever SCD2 state for a new customer
        (
            batch_seq = 1
            AND warehouse_customer_sk IS NULL
        )


        -- Existing / later customer state change
        OR city
            IS DISTINCT FROM prev_city

        OR state
            IS DISTINCT FROM prev_state

        OR country
            IS DISTINCT FROM prev_country

        OR postal_code
            IS DISTINCT FROM prev_postal_code

        OR customer_status
            IS DISTINCT FROM prev_customer_status
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
-- 10. Safety guard:
-- rebuilt NORMAL SCD2 periods must be positive duration
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

SELECT
    COUNT(*)::INTEGER

FROM tmp_scd2_changes

WHERE next_effective_at IS NOT NULL

  AND next_effective_at <= effective_at;



-- ============================================================
-- 11. Close current warehouse row
--
-- Only the first REAL SCD2 change for each customer closes
-- the previously current warehouse row.
-- ============================================================

UPDATE warehouse.dim_customer d

SET
    valid_to =
        c.effective_at,

    is_current =
        FALSE

FROM tmp_scd2_changes c

WHERE c.change_seq = 1

  AND c.warehouse_customer_sk
        IS NOT NULL

  AND d.customer_sk =
      c.warehouse_customer_sk

  AND d.is_current = TRUE;



-- ============================================================
-- 12. Insert complete NORMAL SCD2 chain
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
-- 13. Latest NORMAL snapshot/customer for Type 1
--
-- IMPORTANT:
--
-- Type 1 is independent of whether the NORMAL version caused
-- an SCD2 change.
--
-- Late historical versions are deferred to V3 and therefore
-- do not overwrite newer Type 1 state here.
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
-- 14. Apply Type 1 attributes across all customer history
-- ============================================================

UPDATE warehouse.dim_customer d

SET
    first_name =
        t.first_name,

    last_name =
        t.last_name,

    email =
        t.email,

    phone =
        t.phone,

    date_of_birth =
        t.date_of_birth,

    signup_date =
        t.signup_date

FROM tmp_latest_type1 t

WHERE d.customer_id =
      t.customer_id;



-- ============================================================
-- 15. Advance main watermark
--
-- IMPORTANT:
--
-- Watermark advances using ALL staging rows:
--
--   NORMAL rows -> processed by V2
--   LATE rows   -> durably handed to V3 queue
--
-- Therefore both categories are safely accounted for.
-- ============================================================

UPDATE control.pipeline_watermark w

SET
    last_processed_version_id =
        x.max_version_id,

    updated_at =
        clock_timestamp()

FROM (

    SELECT
        MAX(customer_version_id)
            AS max_version_id

    FROM tmp_all_batch

) x

WHERE w.pipeline_name =
      'dim_customer_incremental'

  AND x.max_version_id IS NOT NULL

  AND x.max_version_id >
      w.last_processed_version_id;



-- ============================================================
-- 16. Mark audit SUCCESS
--
-- This is inside the SAME transaction as:
--
--   queue handoff
--   warehouse changes
--   watermark advancement
-- ============================================================

UPDATE audit.etl_runs e

SET
    finished_at =
        clock_timestamp(),

    status =
        'SUCCESS',

    watermark_before =
        r.watermark_before,

    watermark_after =
        w.last_processed_version_id,


    -- All unprocessed staging rows seen by this run
    rows_in_batch = (

        SELECT COUNT(*)::INTEGER
        FROM tmp_all_batch

    ),


    -- Actual new SCD2 dimension rows
    scd2_rows_inserted = (

        SELECT COUNT(*)::INTEGER
        FROM tmp_scd2_changes

    ),


    -- NORMAL customers receiving Type1 propagation
    type1_customers_affected = (

        SELECT COUNT(*)::INTEGER
        FROM tmp_latest_type1

    ),


    -- Versions handed to V3 repair workflow
    late_rows_queued = (

        SELECT COUNT(*)::INTEGER
        FROM tmp_late_batch

    ),


    error_message =
        NULL


FROM tmp_run_context r

JOIN control.pipeline_watermark w

    ON w.pipeline_name =
       'dim_customer_incremental'

WHERE e.run_id =
      r.run_id;



-- ============================================================
-- 17. Commit everything atomically
-- ============================================================

COMMIT;



-- ============================================================
-- 18. Display persisted ETL run
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

    e.late_rows_queued,

    e.error_message

FROM audit.etl_runs e

JOIN tmp_run_context r
    ON e.run_id = r.run_id;



-- ============================================================
-- 19. Display late arrivals detected by this run
-- ============================================================

SELECT
    q.late_arrival_id,
    q.customer_version_id,
    q.customer_id,
    q.effective_at,
    q.status,
    q.repair_action,
    q.detected_run_id

FROM control.customer_late_arrival_queue q

JOIN tmp_run_context r
    ON q.detected_run_id = r.run_id

ORDER BY q.customer_version_id;



-- ============================================================
-- 20. Clean session state
-- ============================================================

DROP TABLE tmp_run_context;


\set ON_ERROR_STOP off