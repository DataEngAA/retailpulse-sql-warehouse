INSERT INTO staging.stg_products (

    raw_record_id,
    product_id,
    product_name,
    category,
    brand,
    product_status,
    source_system,
    batch_id,
    ingested_at

)

SELECT

    p.raw_record_id,

    BTRIM(p.product_id)::BIGINT,

    BTRIM(p.product_name),

    NULLIF(BTRIM(p.category), ''),

    NULLIF(BTRIM(p.brand), ''),

    UPPER(NULLIF(BTRIM(p.product_status), '')),

    p.source_system,

    p.batch_id,

    p.ingested_at

FROM raw.products p

WHERE NOT EXISTS (

    SELECT 1

    FROM audit.data_quality_issues q

    WHERE q.source_schema = 'raw'
      AND q.source_table = 'products'
      AND q.raw_record_id = p.raw_record_id
      AND q.action = 'REJECT'

)

AND NOT EXISTS (

    SELECT 1

    FROM staging.stg_products s

    WHERE s.raw_record_id = p.raw_record_id

);