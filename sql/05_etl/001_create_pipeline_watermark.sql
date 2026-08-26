CREATE TABLE IF NOT EXISTS control.pipeline_watermark (
    pipeline_name TEXT PRIMARY KEY,

    last_processed_version_id BIGINT NOT NULL DEFAULT 0,

    updated_at TIMESTAMPTZ NOT NULL
        DEFAULT CURRENT_TIMESTAMP
);
INSERT INTO control.pipeline_watermark (
    pipeline_name,
    last_processed_version_id
)
SELECT
    'dim_customer_incremental',
    COALESCE(MAX(customer_version_id), 0)
FROM staging.stg_customer_versions

ON CONFLICT (pipeline_name) DO NOTHING;