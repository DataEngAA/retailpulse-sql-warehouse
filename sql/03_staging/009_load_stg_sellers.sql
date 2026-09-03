INSERT INTO staging.stg_sellers (

    raw_record_id,
    seller_id,
    seller_name,
    seller_status,
    country,
    source_system,
    batch_id,
    ingested_at

)

SELECT

    s.raw_record_id,

    BTRIM(s.seller_id)::BIGINT,

    BTRIM(s.seller_name),

    UPPER(NULLIF(BTRIM(s.seller_status), '')),

    NULLIF(BTRIM(s.country), ''),

    s.source_system,

    s.batch_id,

    s.ingested_at

FROM raw.sellers s

WHERE NOT EXISTS (

    SELECT 1

    FROM audit.data_quality_issues q

    WHERE q.source_schema = 'raw'
      AND q.source_table = 'sellers'
      AND q.raw_record_id = s.raw_record_id
      AND q.action = 'REJECT'

)

AND NOT EXISTS (

    SELECT 1

    FROM staging.stg_sellers st

    WHERE st.raw_record_id = s.raw_record_id

);