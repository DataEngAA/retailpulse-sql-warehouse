INSERT INTO audit.data_quality_issues (
    source_schema,
    source_table,
    raw_record_id,
    field_name,
    issue_code,
    severity,
    action,
    original_value
)
SELECT
    'raw',
    'customers',
    raw_record_id,
    'customer_id',
    'missing_customer_id',
    'ERROR',
    'REJECT',
    customer_id
FROM raw.customers
WHERE NULLIF(BTRIM(customer_id), '') IS NULL
ON CONFLICT DO NOTHING;

INSERT INTO audit.data_quality_issues (
    source_schema,
    source_table,
    raw_record_id,
    field_name,
    issue_code,
    severity,
    action,
    original_value
)
SELECT
    'raw',
    'customers',
    raw_record_id,
    'customer_id',
    'invalid_customer_id',
    'ERROR',
    'REJECT',
    customer_id
FROM raw.customers
WHERE NULLIF(BTRIM(customer_id), '') IS NOT NULL
  AND (
        NOT pg_input_is_valid(BTRIM(customer_id), 'bigint')
        OR (
            pg_input_is_valid(BTRIM(customer_id), 'bigint')
            AND BTRIM(customer_id)::BIGINT <= 0
        )
      )
ON CONFLICT DO NOTHING;

INSERT INTO audit.data_quality_issues (
    source_schema,
    source_table,
    raw_record_id,
    field_name,
    issue_code,
    severity,
    action,
    original_value
)
SELECT
    'raw',
    'customers',
    raw_record_id,
    'email',
    'email_needs_normalization',
    'WARNING',
    'CLEAN',
    email
FROM raw.customers
WHERE email IS NOT NULL
  AND email <> LOWER(BTRIM(email))
ON CONFLICT DO NOTHING;

INSERT INTO audit.data_quality_issues (
    source_schema,
    source_table,
    raw_record_id,
    field_name,
    issue_code,
    severity,
    action,
    original_value
)
SELECT
    'raw',
    'customers',
    raw_record_id,
    'email',
    'invalid_email',
    'WARNING',
    'NULLIFY',
    email
FROM raw.customers
WHERE NULLIF(BTRIM(email), '') IS NOT NULL
  AND BTRIM(email) !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$'
ON CONFLICT DO NOTHING;

INSERT INTO audit.data_quality_issues (
    source_schema,
    source_table,
    raw_record_id,
    field_name,
    issue_code,
    severity,
    action,
    original_value
)
SELECT
    'raw',
    'customers',
    raw_record_id,
    'city',
    'missing_city',
    'WARNING',
    'FLAG',
    city
FROM raw.customers
WHERE NULLIF(BTRIM(city), '') IS NULL
ON CONFLICT DO NOTHING;

INSERT INTO audit.data_quality_issues (
    source_schema,
    source_table,
    raw_record_id,
    field_name,
    issue_code,
    severity,
    action,
    original_value
)
SELECT
    'raw',
    'customers',
    raw_record_id,
    'updated_at',
    'invalid_updated_at',
    'WARNING',
    'FALLBACK',
    updated_at
FROM raw.customers
WHERE NULLIF(BTRIM(updated_at), '') IS NOT NULL
  AND NOT pg_input_is_valid(BTRIM(updated_at), 'timestamptz')
ON CONFLICT DO NOTHING;

INSERT INTO audit.data_quality_issues (
    source_schema,
    source_table,
    raw_record_id,
    field_name,
    issue_code,
    severity,
    action,
    original_value
)
SELECT
    'raw',
    'customers',
    raw_record_id,
    'updated_at',
    'missing_updated_at',
    'WARNING',
    'FALLBACK',
    updated_at
FROM raw.customers
WHERE NULLIF(BTRIM(updated_at), '') IS NULL
ON CONFLICT DO NOTHING;