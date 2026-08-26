CREATE OR REPLACE VIEW staging.stg_customers_current AS

WITH ranked_customers AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY
                effective_at DESC,
                customer_version_id DESC
        ) AS version_rank
    FROM staging.stg_customer_versions
)

SELECT
    customer_version_id,
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
    ingested_at,
    staged_at
FROM ranked_customers
WHERE version_rank = 1;