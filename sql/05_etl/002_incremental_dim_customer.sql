BEGIN;


-- ============================================================
-- 1. Collect all unprocessed customer versions
-- ============================================================

CREATE TEMP TABLE tmp_customer_changes
ON COMMIT DROP
AS

SELECT
    s.*,

    d.customer_sk AS current_customer_sk,

    CASE
        WHEN d.customer_sk IS NULL
            THEN 'NEW_CUSTOMER'

        WHEN s.city IS DISTINCT FROM d.city
          OR s.state IS DISTINCT FROM d.state
          OR s.country IS DISTINCT FROM d.country
          OR s.postal_code IS DISTINCT FROM d.postal_code
          OR s.customer_status IS DISTINCT FROM d.customer_status
            THEN 'SCD2_CHANGE'

        ELSE 'TYPE1_ONLY'
    END AS required_action

FROM staging.stg_customer_versions s

LEFT JOIN warehouse.dim_customer d
    ON s.customer_id = d.customer_id
   AND d.is_current = TRUE

WHERE s.customer_version_id >
(
    SELECT last_processed_version_id
    FROM control.pipeline_watermark
    WHERE pipeline_name = 'dim_customer_incremental'
);


-- V1 safety rule:
-- only one incoming version per customer per run.
-- If this fails, the whole transaction fails.
CREATE UNIQUE INDEX tmp_one_change_per_customer
ON tmp_customer_changes(customer_id);



-- ============================================================
-- 2. Close current rows where an SCD2 attribute changed
-- ============================================================

UPDATE warehouse.dim_customer d

SET
    valid_to = c.effective_at,
    is_current = FALSE

FROM tmp_customer_changes c

WHERE c.required_action = 'SCD2_CHANGE'
  AND d.customer_id = c.customer_id
  AND d.is_current = TRUE;



-- ============================================================
-- 3. Insert first version of new customers
--    OR new SCD2 versions
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
    NULL,
    TRUE,

    raw_record_id

FROM tmp_customer_changes

WHERE required_action IN (
    'NEW_CUSTOMER',
    'SCD2_CHANGE'
);



-- ============================================================
-- 4. Apply latest Type 1 values across customer history
-- ============================================================

UPDATE warehouse.dim_customer d

SET
    first_name    = c.first_name,
    last_name     = c.last_name,
    email         = c.email,
    phone         = c.phone,
    date_of_birth = c.date_of_birth,
    signup_date   = c.signup_date

FROM tmp_customer_changes c

WHERE d.customer_id = c.customer_id;



-- ============================================================
-- 5. Move watermark only after warehouse changes succeeded
-- ============================================================

UPDATE control.pipeline_watermark w

SET
    last_processed_version_id = x.max_version_id,
    updated_at = CURRENT_TIMESTAMP

FROM (
    SELECT MAX(customer_version_id) AS max_version_id
    FROM tmp_customer_changes
) x

WHERE w.pipeline_name = 'dim_customer_incremental'
  AND x.max_version_id IS NOT NULL;


COMMIT;