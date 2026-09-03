INSERT INTO staging.stg_orders (

    raw_record_id,
    order_id,
    customer_id,
    order_status,
    order_created_at,
    order_updated_at,
    currency,
    shipping_amount,
    order_discount_amount,
    source_system,
    batch_id,
    ingested_at

)

SELECT

    r.raw_record_id,

    BTRIM(r.order_id)::BIGINT,

    BTRIM(r.customer_id)::BIGINT,

    UPPER(BTRIM(r.order_status)),

    BTRIM(r.order_created_at)::TIMESTAMPTZ,


    -- Invalid/missing updated timestamp becomes NULL
    CASE
        WHEN r.order_updated_at IS NOT NULL
         AND BTRIM(r.order_updated_at) <> ''
         AND pg_input_is_valid(
                BTRIM(r.order_updated_at),
                'timestamptz'
             )
        THEN BTRIM(r.order_updated_at)::TIMESTAMPTZ

        ELSE NULL
    END,


    UPPER(BTRIM(r.currency)),


    -- Invalid shipping was marked NULLIFY,
    -- therefore staging converts it to NULL
    CASE
        WHEN r.shipping_amount IS NOT NULL
         AND BTRIM(r.shipping_amount) <> ''
         AND pg_input_is_valid(
                BTRIM(r.shipping_amount),
                'numeric'
             )
        THEN BTRIM(r.shipping_amount)::NUMERIC(18,2)

        ELSE NULL
    END,


    CASE
        WHEN r.order_discount_amount IS NOT NULL
         AND BTRIM(r.order_discount_amount) <> ''
         AND pg_input_is_valid(
                BTRIM(r.order_discount_amount),
                'numeric'
             )
        THEN BTRIM(r.order_discount_amount)::NUMERIC(18,2)

        ELSE NULL
    END,


    r.source_system,
    r.batch_id,
    r.ingested_at


FROM raw.orders r


-- Do NOT load rows that have a REJECT issue
WHERE NOT EXISTS (

    SELECT 1

    FROM audit.data_quality_issues q

    WHERE q.source_schema = 'raw'

      AND q.source_table = 'orders'

      AND q.raw_record_id = r.raw_record_id

      AND q.action = 'REJECT'

)


-- Don't reload the same RAW row twice
AND NOT EXISTS (

    SELECT 1

    FROM staging.stg_orders s

    WHERE s.raw_record_id = r.raw_record_id

);