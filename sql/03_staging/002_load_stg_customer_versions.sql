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
    r.raw_record_id,

    BTRIM(r.customer_id)::BIGINT,

    NULLIF(BTRIM(r.first_name), ''),
    NULLIF(BTRIM(r.last_name), ''),

    CASE
        WHEN NULLIF(BTRIM(r.email), '') IS NULL
            THEN NULL

        WHEN BTRIM(r.email) ~*
             '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$'
            THEN LOWER(BTRIM(r.email))

        ELSE NULL
    END,

    NULLIF(BTRIM(r.phone), ''),

    CASE
        WHEN NULLIF(BTRIM(r.date_of_birth), '') IS NOT NULL
             AND pg_input_is_valid(BTRIM(r.date_of_birth), 'date')
        THEN BTRIM(r.date_of_birth)::DATE
        ELSE NULL
    END,

    NULLIF(INITCAP(BTRIM(r.city)), ''),
    NULLIF(INITCAP(BTRIM(r.state)), ''),
    NULLIF(INITCAP(BTRIM(r.country)), ''),
    NULLIF(BTRIM(r.postal_code), ''),

    CASE
        WHEN NULLIF(BTRIM(r.signup_date), '') IS NOT NULL
             AND pg_input_is_valid(BTRIM(r.signup_date), 'date')
        THEN BTRIM(r.signup_date)::DATE
        ELSE NULL
    END,

    CASE
        WHEN NULLIF(BTRIM(r.customer_status), '') IS NULL
            THEN NULL
        ELSE LOWER(BTRIM(r.customer_status))
    END,

    CASE
        WHEN NULLIF(BTRIM(r.created_at), '') IS NOT NULL
             AND pg_input_is_valid(BTRIM(r.created_at), 'timestamptz')
        THEN BTRIM(r.created_at)::TIMESTAMPTZ
        ELSE NULL
    END,

    CASE
        WHEN NULLIF(BTRIM(r.updated_at), '') IS NOT NULL
             AND pg_input_is_valid(BTRIM(r.updated_at), 'timestamptz')
        THEN BTRIM(r.updated_at)::TIMESTAMPTZ
        ELSE NULL
    END,

    CASE
        WHEN NULLIF(BTRIM(r.updated_at), '') IS NOT NULL
             AND pg_input_is_valid(BTRIM(r.updated_at), 'timestamptz')
        THEN BTRIM(r.updated_at)::TIMESTAMPTZ

        WHEN NULLIF(BTRIM(r.created_at), '') IS NOT NULL
             AND pg_input_is_valid(BTRIM(r.created_at), 'timestamptz')
        THEN BTRIM(r.created_at)::TIMESTAMPTZ

        ELSE r.ingested_at
    END,

    CASE
        WHEN NULLIF(BTRIM(r.updated_at), '') IS NOT NULL
             AND pg_input_is_valid(BTRIM(r.updated_at), 'timestamptz')
        THEN 'updated_at'

        WHEN NULLIF(BTRIM(r.created_at), '') IS NOT NULL
             AND pg_input_is_valid(BTRIM(r.created_at), 'timestamptz')
        THEN 'created_at'

        ELSE 'ingested_at'
    END,

    r.source_system,
    r.batch_id,
    r.ingested_at

FROM raw.customers r

WHERE NOT EXISTS (
    SELECT 1
    FROM audit.data_quality_issues q
    WHERE q.source_schema = 'raw'
      AND q.source_table = 'customers'
      AND q.raw_record_id = r.raw_record_id
      AND q.action = 'REJECT'
)

ON CONFLICT (raw_record_id) DO NOTHING;