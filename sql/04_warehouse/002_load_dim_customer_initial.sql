TRUNCATE TABLE warehouse.dim_customer RESTART IDENTITY;


WITH version_compare AS (

    SELECT
        *,

        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY effective_at, customer_version_id
        ) AS version_number,

        LAG(city) OVER (
            PARTITION BY customer_id
            ORDER BY effective_at, customer_version_id
        ) AS previous_city,

        LAG(state) OVER (
            PARTITION BY customer_id
            ORDER BY effective_at, customer_version_id
        ) AS previous_state,

        LAG(country) OVER (
            PARTITION BY customer_id
            ORDER BY effective_at, customer_version_id
        ) AS previous_country,

        LAG(postal_code) OVER (
            PARTITION BY customer_id
            ORDER BY effective_at, customer_version_id
        ) AS previous_postal_code,

        LAG(customer_status) OVER (
            PARTITION BY customer_id
            ORDER BY effective_at, customer_version_id
        ) AS previous_customer_status

    FROM staging.stg_customer_versions
),


change_detection AS (

    SELECT
        *,

        CASE
            WHEN version_number = 1 THEN 1

            WHEN city IS DISTINCT FROM previous_city
              OR state IS DISTINCT FROM previous_state
              OR country IS DISTINCT FROM previous_country
              OR postal_code IS DISTINCT FROM previous_postal_code
              OR customer_status IS DISTINCT FROM previous_customer_status
            THEN 1

            ELSE 0
        END AS starts_new_scd2_version

    FROM version_compare
),


scd_groups AS (

    SELECT
        *,

        SUM(starts_new_scd2_version) OVER (
            PARTITION BY customer_id
            ORDER BY effective_at, customer_version_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS scd_group

    FROM change_detection
),


group_ranked AS (

    SELECT
        *,

        ROW_NUMBER() OVER (
            PARTITION BY customer_id, scd_group
            ORDER BY effective_at, customer_version_id
        ) AS group_start_rank

    FROM scd_groups
),


group_attributes AS (

    SELECT
        customer_id,
        scd_group,

        city,
        state,
        country,
        postal_code,
        customer_status,

        raw_record_id AS source_raw_record_id

    FROM group_ranked

    WHERE group_start_rank = 1
),


grouped_history AS (

    SELECT
        customer_id,
        scd_group,
        MIN(effective_at) AS valid_from

    FROM scd_groups

    GROUP BY
        customer_id,
        scd_group
),


periodized_history AS (

    SELECT
        customer_id,
        scd_group,
        valid_from,

        LEAD(valid_from) OVER (
            PARTITION BY customer_id
            ORDER BY scd_group
        ) AS valid_to

    FROM grouped_history
),


latest_type1_ranked AS (

    SELECT
        customer_id,
        first_name,
        last_name,
        email,
        phone,
        date_of_birth,
        signup_date,

        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY effective_at DESC, customer_version_id DESC
        ) AS rn

    FROM staging.stg_customer_versions
),


latest_type1 AS (

    SELECT
        customer_id,
        first_name,
        last_name,
        email,
        phone,
        date_of_birth,
        signup_date

    FROM latest_type1_ranked

    WHERE rn = 1
)


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
    p.customer_id,

    t.first_name,
    t.last_name,
    t.email,
    t.phone,
    t.date_of_birth,
    t.signup_date,

    g.city,
    g.state,
    g.country,
    g.postal_code,
    g.customer_status,

    p.valid_from,
    p.valid_to,
    p.valid_to IS NULL,

    g.source_raw_record_id

FROM periodized_history p

JOIN group_attributes g
    ON p.customer_id = g.customer_id
   AND p.scd_group = g.scd_group

JOIN latest_type1 t
    ON p.customer_id = t.customer_id

ORDER BY
    p.customer_id,
    p.valid_from;