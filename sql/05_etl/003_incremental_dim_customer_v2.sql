-- ============================================================
-- RetailPulse
-- Incremental Customer Dimension Loader V2
--
-- Supports:
--   - New customers
--   - Type 1 changes
--   - Multiple SCD2 changes/customer/run
--   - No-op snapshots
--
-- Does NOT yet support:
--   - Late-arriving historical versions
-- ============================================================


BEGIN;


-- ============================================================
-- 1. Lock pipeline watermark
--
-- Prevents two copies of this ETL from processing the same
-- watermark simultaneously.
-- ============================================================

SELECT last_processed_version_id
FROM control.pipeline_watermark
WHERE pipeline_name = 'dim_customer_incremental'
FOR UPDATE;

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
    SELECT last_processed_version_id
    FROM control.pipeline_watermark
    WHERE pipeline_name = 'dim_customer_incremental'
);

-- ============================================================
-- 3. Safety guard: reject late-arriving versions
--
-- V2 only appends history after the current warehouse version.
-- Historical corrections will be handled in a later version.
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

SELECT COUNT(*)

FROM tmp_batch b

JOIN warehouse.dim_customer d
    ON b.customer_id = d.customer_id
   AND d.is_current = TRUE

WHERE b.effective_at <= d.valid_from;

-- ============================================================
-- 4. Safety guard: reject conflicting SCD2 states at
--    exactly the same effective timestamp
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

SELECT COUNT(*)

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

) violations;

-- ============================================================
-- 5. Detect real SCD2 changes
--
-- First incoming version:
--     compare against current warehouse state.
--
-- Later versions:
--     compare against previous staging version in the batch.
-- ============================================================

CREATE TEMP TABLE tmp_scd2_changes
ON COMMIT DROP
AS

WITH with_predecessors AS (

    SELECT
        b.*,

        d.customer_sk AS warehouse_customer_sk,

        CASE
            WHEN b.batch_seq = 1 THEN d.city
            ELSE LAG(b.city) OVER (
                PARTITION BY b.customer_id
                ORDER BY b.batch_seq
            )
        END AS prev_city,

        CASE
            WHEN b.batch_seq = 1 THEN d.state
            ELSE LAG(b.state) OVER (
                PARTITION BY b.customer_id
                ORDER BY b.batch_seq
            )
        END AS prev_state,

        CASE
            WHEN b.batch_seq = 1 THEN d.country
            ELSE LAG(b.country) OVER (
                PARTITION BY b.customer_id
                ORDER BY b.batch_seq
            )
        END AS prev_country,

        CASE
            WHEN b.batch_seq = 1 THEN d.postal_code
            ELSE LAG(b.postal_code) OVER (
                PARTITION BY b.customer_id
                ORDER BY b.batch_seq
            )
        END AS prev_postal_code,

        CASE
            WHEN b.batch_seq = 1 THEN d.customer_status
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
        -- First ever warehouse version for a new customer
        (
            batch_seq = 1
            AND warehouse_customer_sk IS NULL
        )

        -- Existing customer whose SCD2 state changed
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
            ORDER BY effective_at, customer_version_id
        ) AS change_seq,

        LEAD(effective_at) OVER (
            PARTITION BY customer_id
            ORDER BY effective_at, customer_version_id
        ) AS next_effective_at

    FROM real_changes
)

SELECT *
FROM periodized;

-- ============================================================
-- 6. Safety guard: SCD2 periods must have positive duration
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

SELECT COUNT(*)

FROM tmp_scd2_changes

WHERE next_effective_at IS NOT NULL
  AND next_effective_at <= effective_at;

-- ============================================================
-- 7. Close the existing current warehouse row
--
-- Only the FIRST real SCD2 change for each existing customer
-- closes the row that was current before this ETL run.
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
-- 8. Insert all new SCD2 versions
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
-- 9. Capture latest incoming snapshot per customer
--
-- Type 1 attributes come from the latest batch version even
-- when the batch contains no SCD2 change.
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
-- 10. Apply latest Type 1 attributes across all historical
--     rows for each affected customer.
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
-- 11. Advance watermark only after warehouse processing
--     has succeeded.
-- ============================================================

UPDATE control.pipeline_watermark w

SET
    last_processed_version_id = x.max_version_id,
    updated_at = CURRENT_TIMESTAMP

FROM (
    SELECT MAX(customer_version_id) AS max_version_id
    FROM tmp_batch
) x

WHERE w.pipeline_name = 'dim_customer_incremental'
  AND x.max_version_id IS NOT NULL
  AND x.max_version_id > w.last_processed_version_id;

  -- ============================================================
-- 12. Commit the entire ETL batch
-- ============================================================

COMMIT;