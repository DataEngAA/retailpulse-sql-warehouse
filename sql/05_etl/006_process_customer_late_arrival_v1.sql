-- ============================================================
-- RetailPulse
-- Customer Late-Arrival Repair Worker V1
--
-- Processes ONE PENDING repair request per execution.
--
-- Supported:
--
--   NO_SCD2_CHANGE
--   SPLIT_INSERT
--   MERGE_WITH_NEXT
--
-- Known unsafe/unsupported cases are marked FAILED rather
-- than allowing ambiguous history to enter the warehouse.
-- ============================================================


\set ON_ERROR_STOP on



-- ============================================================
-- SESSION RESULT CONTEXT
--
-- Survives COMMIT so we can display the processed queue row.
-- ============================================================

DROP TABLE IF EXISTS tmp_v3_result;


CREATE TEMP TABLE tmp_v3_result (

    late_arrival_id BIGINT PRIMARY KEY

)
ON COMMIT PRESERVE ROWS;



-- ============================================================
-- REPAIR TRANSACTION
-- ============================================================

BEGIN;



-- ============================================================
-- 1. Pick ONE oldest PENDING queue item
--
-- FOR UPDATE:
--     lock this repair request
--
-- SKIP LOCKED:
--     another worker could safely pick another row later
-- ============================================================

WITH candidate AS (

    SELECT
        q.late_arrival_id

    FROM control.customer_late_arrival_queue q

    WHERE q.status = 'PENDING'

    ORDER BY q.late_arrival_id

    FOR UPDATE SKIP LOCKED

    LIMIT 1

)

INSERT INTO tmp_v3_result (
    late_arrival_id
)

SELECT late_arrival_id
FROM candidate;



-- ============================================================
-- 2. Build full repair context
--
-- Queue
--   +
-- original staging version
--   +
-- containing warehouse interval
--   +
-- immediately next warehouse interval
-- ============================================================

CREATE TEMP TABLE tmp_v3_context
ON COMMIT DROP
AS

SELECT

    q.late_arrival_id,

    q.customer_version_id,
    q.customer_id AS queued_customer_id,
    q.effective_at AS queued_effective_at,


    -- --------------------------------------------------------
    -- Original staging version
    -- --------------------------------------------------------

    s.raw_record_id,

    s.customer_id AS staging_customer_id,

    s.first_name AS staging_first_name,
    s.last_name AS staging_last_name,
    s.email AS staging_email,
    s.phone AS staging_phone,
    s.date_of_birth AS staging_date_of_birth,
    s.signup_date AS staging_signup_date,

    s.city AS incoming_city,
    s.state AS incoming_state,
    s.country AS incoming_country,
    s.postal_code AS incoming_postal_code,
    s.customer_status AS incoming_customer_status,

    s.effective_at AS incoming_effective_at,


    -- --------------------------------------------------------
    -- Containing warehouse interval
    -- --------------------------------------------------------

    c.customer_sk AS containing_customer_sk,

    c.first_name AS warehouse_first_name,
    c.last_name AS warehouse_last_name,
    c.email AS warehouse_email,
    c.phone AS warehouse_phone,
    c.date_of_birth AS warehouse_date_of_birth,
    c.signup_date AS warehouse_signup_date,

    c.city AS containing_city,
    c.state AS containing_state,
    c.country AS containing_country,
    c.postal_code AS containing_postal_code,
    c.customer_status AS containing_customer_status,

    c.valid_from AS containing_valid_from,
    c.valid_to AS containing_valid_to,
    c.is_current AS containing_is_current,


    -- --------------------------------------------------------
    -- Immediately next interval
    -- --------------------------------------------------------

    n.customer_sk AS next_customer_sk,

    n.city AS next_city,
    n.state AS next_state,
    n.country AS next_country,
    n.postal_code AS next_postal_code,
    n.customer_status AS next_customer_status,

    n.valid_from AS next_valid_from,
    n.valid_to AS next_valid_to


FROM tmp_v3_result r


JOIN control.customer_late_arrival_queue q

    ON q.late_arrival_id =
       r.late_arrival_id


LEFT JOIN staging.stg_customer_versions s

    ON s.customer_version_id =
       q.customer_version_id


LEFT JOIN warehouse.dim_customer c

    ON c.customer_id =
       s.customer_id

   AND tstzrange(
        c.valid_from,
        c.valid_to,
        '[)'
   ) @> s.effective_at


LEFT JOIN warehouse.dim_customer n

    ON n.customer_id =
       c.customer_id

   AND n.valid_from =
       c.valid_to;



-- ============================================================
-- 3. Classify repair
--
-- Internal decisions:
--
-- FAILED
-- NO_SCD2_CHANGE
-- SPLIT_INSERT
-- MERGE_WITH_NEXT
-- ============================================================

CREATE TEMP TABLE tmp_v3_classified
ON COMMIT DROP
AS

SELECT
    x.*,


    CASE

        -- ----------------------------------------------------
        -- Original staging version disappeared
        -- ----------------------------------------------------

        WHEN x.raw_record_id IS NULL

            THEN 'FAILED'


        -- ----------------------------------------------------
        -- Queue metadata should still agree with staging
        -- ----------------------------------------------------

        WHEN x.queued_customer_id
                IS DISTINCT FROM
             x.staging_customer_id

          OR x.queued_effective_at
                IS DISTINCT FROM
             x.incoming_effective_at

            THEN 'FAILED'


        -- ----------------------------------------------------
        -- Timestamp does not fit any warehouse interval
        --
        -- Example:
        -- event predates all known customer history
        -- ----------------------------------------------------

        WHEN x.containing_customer_sk IS NULL

            THEN 'FAILED'


        -- ----------------------------------------------------
        -- Another staging row claims a DIFFERENT SCD2 state
        -- at the exact same business timestamp.
        --
        -- Technical version IDs cannot resolve this safely.
        -- ----------------------------------------------------

        WHEN EXISTS (

            SELECT 1

            FROM staging.stg_customer_versions s2

            WHERE s2.customer_id =
                  x.staging_customer_id

              AND s2.effective_at =
                  x.incoming_effective_at

              AND s2.customer_version_id <>
                  x.customer_version_id

              AND ROW(
                    s2.city,
                    s2.state,
                    s2.country,
                    s2.postal_code,
                    s2.customer_status
                  )
                  IS DISTINCT FROM
                  ROW(
                    x.incoming_city,
                    x.incoming_state,
                    x.incoming_country,
                    x.incoming_postal_code,
                    x.incoming_customer_status
                  )

        )

            THEN 'FAILED'


        -- ----------------------------------------------------
        -- Incoming SCD2 state already exists throughout
        -- containing interval.
        -- ----------------------------------------------------

        WHEN ROW(
                x.incoming_city,
                x.incoming_state,
                x.incoming_country,
                x.incoming_postal_code,
                x.incoming_customer_status
             )
             IS NOT DISTINCT FROM
             ROW(
                x.containing_city,
                x.containing_state,
                x.containing_country,
                x.containing_postal_code,
                x.containing_customer_status
             )

            THEN 'NO_SCD2_CHANGE'


        -- ----------------------------------------------------
        -- Different state exactly at an existing valid_from.
        --
        -- Splitting here would create a zero-duration left row.
        -- V1 fails closed instead of guessing replacement logic.
        -- ----------------------------------------------------

        WHEN x.incoming_effective_at =
             x.containing_valid_from

            THEN 'FAILED'


        -- ----------------------------------------------------
        -- Late state already equals next historical state.
        --
        -- Extend existing next row backward.
        -- ----------------------------------------------------

        WHEN x.next_customer_sk IS NOT NULL

         AND ROW(
                x.incoming_city,
                x.incoming_state,
                x.incoming_country,
                x.incoming_postal_code,
                x.incoming_customer_status
             )
             IS NOT DISTINCT FROM
             ROW(
                x.next_city,
                x.next_state,
                x.next_country,
                x.next_postal_code,
                x.next_customer_status
             )

            THEN 'MERGE_WITH_NEXT'


        -- ----------------------------------------------------
        -- Genuine new historical state
        -- ----------------------------------------------------

        ELSE 'SPLIT_INSERT'

    END AS repair_decision,


    CASE

        WHEN x.raw_record_id IS NULL

            THEN
            'Original staging version not found.'


        WHEN x.queued_customer_id
                IS DISTINCT FROM
             x.staging_customer_id

          OR x.queued_effective_at
                IS DISTINCT FROM
             x.incoming_effective_at

            THEN
            'Queue metadata does not match the original staging version.'


        WHEN x.containing_customer_sk IS NULL

            THEN
            'No warehouse validity interval contains the late effective_at.'


        WHEN EXISTS (

            SELECT 1

            FROM staging.stg_customer_versions s2

            WHERE s2.customer_id =
                  x.staging_customer_id

              AND s2.effective_at =
                  x.incoming_effective_at

              AND s2.customer_version_id <>
                  x.customer_version_id

              AND ROW(
                    s2.city,
                    s2.state,
                    s2.country,
                    s2.postal_code,
                    s2.customer_status
                  )
                  IS DISTINCT FROM
                  ROW(
                    x.incoming_city,
                    x.incoming_state,
                    x.incoming_country,
                    x.incoming_postal_code,
                    x.incoming_customer_status
                  )
        )

            THEN
            'Conflicting SCD2 states exist at the same business timestamp.'


        WHEN ROW(
                x.incoming_city,
                x.incoming_state,
                x.incoming_country,
                x.incoming_postal_code,
                x.incoming_customer_status
             )
             IS NOT DISTINCT FROM
             ROW(
                x.containing_city,
                x.containing_state,
                x.containing_country,
                x.containing_postal_code,
                x.containing_customer_status
             )

            THEN NULL


        WHEN x.incoming_effective_at =
             x.containing_valid_from

            THEN
            'Different SCD2 state at an existing interval boundary is unsupported by V3 V1.'


        ELSE NULL

    END AS classification_error


FROM tmp_v3_context x;



-- ============================================================
-- 4. SPLIT / MERGE:
-- shorten containing interval FIRST
--
-- This preserves its existing surrogate key.
--
-- It must happen before MERGE_WITH_NEXT moves the next
-- interval backward, otherwise the exclusion constraint could
-- detect temporary overlap.
-- ============================================================

UPDATE warehouse.dim_customer d

SET
    valid_to =
        x.incoming_effective_at,

    is_current =
        FALSE

FROM tmp_v3_classified x

WHERE x.repair_decision IN (
        'SPLIT_INSERT',
        'MERGE_WITH_NEXT'
      )

  AND d.customer_sk =
      x.containing_customer_sk;



-- ============================================================
-- 5. MERGE_WITH_NEXT
--
-- Incoming state already equals next state.
--
-- Preserve next customer's surrogate key and extend that
-- interval backward.
--
-- The late raw record becomes the source that establishes
-- the earlier valid_from.
-- ============================================================

UPDATE warehouse.dim_customer d

SET
    valid_from =
        x.incoming_effective_at,

    source_raw_record_id =
        x.raw_record_id

FROM tmp_v3_classified x

WHERE x.repair_decision =
      'MERGE_WITH_NEXT'

  AND d.customer_sk =
      x.next_customer_sk;



-- ============================================================
-- 6. SPLIT_INSERT
--
-- Insert only the genuinely new SCD2 state.
--
-- IMPORTANT TYPE-1 RULE:
--
-- We use Type-1 attributes from the existing warehouse row,
-- NOT from the late historical staging record.
--
-- Why?
-- Type-1 represents the latest known value and has already
-- been propagated across warehouse history by V2.
-- A historical event must not overwrite it with old values.
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

    staging_customer_id,

    warehouse_first_name,
    warehouse_last_name,
    warehouse_email,
    warehouse_phone,
    warehouse_date_of_birth,
    warehouse_signup_date,

    incoming_city,
    incoming_state,
    incoming_country,
    incoming_postal_code,
    incoming_customer_status,

    incoming_effective_at,

    containing_valid_to,

    containing_valid_to IS NULL,

    raw_record_id

FROM tmp_v3_classified

WHERE repair_decision =
      'SPLIT_INSERT';



-- ============================================================
-- 7. Mark recognised data problems FAILED
--
-- These are committed failures:
-- the worker inspected the repair request and determined that
-- it is unsafe / unsupported.
-- ============================================================

UPDATE control.customer_late_arrival_queue q

SET
    status =
        'FAILED',

    repair_action =
        NULL,

    processed_at =
        clock_timestamp(),

    error_message =
        x.classification_error

FROM tmp_v3_classified x

WHERE x.repair_decision =
      'FAILED'

  AND q.late_arrival_id =
      x.late_arrival_id;



-- ============================================================
-- 8. Mark successful repairs SUCCESS
-- ============================================================

UPDATE control.customer_late_arrival_queue q

SET
    status =
        'SUCCESS',

    repair_action =
        x.repair_decision,

    processed_at =
        clock_timestamp(),

    error_message =
        NULL

FROM tmp_v3_classified x

WHERE x.repair_decision IN (

        'NO_SCD2_CHANGE',
        'SPLIT_INSERT',
        'MERGE_WITH_NEXT'

      )

  AND q.late_arrival_id =
      x.late_arrival_id;



-- ============================================================
-- 9. Commit repair atomically
--
-- Warehouse mutation + queue status commit together.
--
-- Unexpected SQL/database failure:
--     everything rolls back
--     queue stays PENDING
--
-- Recognised unsafe data:
--     queue becomes FAILED
--     no warehouse mutation
-- ============================================================

COMMIT;



-- ============================================================
-- 10. Display processed repair
--
-- Empty queue:
-- returns 0 rows.
-- ============================================================

SELECT

    q.late_arrival_id,
    q.customer_version_id,
    q.customer_id,
    q.effective_at,

    q.status,
    q.repair_action,

    q.detected_run_id,

    q.detected_at,
    q.processed_at,

    q.error_message

FROM control.customer_late_arrival_queue q

JOIN tmp_v3_result r

    ON q.late_arrival_id =
       r.late_arrival_id;



DROP TABLE tmp_v3_result;


\set ON_ERROR_STOP off