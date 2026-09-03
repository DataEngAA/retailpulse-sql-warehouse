WITH prepared_returns AS (

    SELECT
        r.*,

        CASE
            WHEN r.return_id IS NOT NULL
             AND BTRIM(r.return_id) <> ''
             AND pg_input_is_valid(
                    BTRIM(r.return_id),
                    'bigint'
                 )
            THEN BTRIM(r.return_id)::BIGINT
            ELSE NULL
        END AS return_id_typed,


        CASE
            WHEN r.order_item_id IS NOT NULL
             AND BTRIM(r.order_item_id) <> ''
             AND pg_input_is_valid(
                    BTRIM(r.order_item_id),
                    'bigint'
                 )
            THEN BTRIM(r.order_item_id)::BIGINT
            ELSE NULL
        END AS order_item_id_typed,


        CASE
            WHEN r.return_quantity IS NOT NULL
             AND BTRIM(r.return_quantity) <> ''
             AND pg_input_is_valid(
                    BTRIM(r.return_quantity),
                    'numeric'
                 )
            THEN BTRIM(r.return_quantity)::NUMERIC(18,4)
            ELSE NULL
        END AS return_quantity_typed,


        CASE
            WHEN r.refund_amount IS NOT NULL
             AND BTRIM(r.refund_amount) <> ''
             AND pg_input_is_valid(
                    BTRIM(r.refund_amount),
                    'numeric'
                 )
            THEN BTRIM(r.refund_amount)::NUMERIC(18,2)
            ELSE NULL
        END AS refund_amount_typed,


        CASE
            WHEN r.requested_at IS NOT NULL
             AND BTRIM(r.requested_at) <> ''
             AND pg_input_is_valid(
                    BTRIM(r.requested_at),
                    'timestamptz'
                 )
            THEN BTRIM(r.requested_at)::TIMESTAMPTZ
            ELSE NULL
        END AS requested_at_typed,


        CASE
            WHEN r.completed_at IS NOT NULL
             AND BTRIM(r.completed_at) <> ''
             AND pg_input_is_valid(
                    BTRIM(r.completed_at),
                    'timestamptz'
                 )
            THEN BTRIM(r.completed_at)::TIMESTAMPTZ
            ELSE NULL
        END AS completed_at_typed

    FROM raw.returns r
)

INSERT INTO staging.stg_returns (

    raw_record_id,

    return_id,
    order_item_id,

    return_status,

    return_quantity,
    refund_amount,

    return_reason,

    requested_at,
    completed_at,

    source_system,
    batch_id,
    ingested_at

)

SELECT

    r.raw_record_id,

    r.return_id_typed,

    r.order_item_id_typed,

    UPPER(NULLIF(BTRIM(r.return_status), '')),

    r.return_quantity_typed,

    r.refund_amount_typed,

    NULLIF(BTRIM(r.return_reason), ''),

    r.requested_at_typed,

    r.completed_at_typed,

    r.source_system,
    r.batch_id,
    r.ingested_at

FROM prepared_returns r

WHERE NOT EXISTS (

    SELECT 1

    FROM audit.data_quality_issues q

    WHERE q.source_schema = 'raw'
      AND q.source_table = 'returns'
      AND q.raw_record_id = r.raw_record_id
      AND q.action = 'REJECT'
)

AND r.return_id_typed IS NOT NULL

AND r.order_item_id_typed IS NOT NULL

AND r.return_quantity_typed IS NOT NULL

AND r.refund_amount_typed IS NOT NULL

AND r.requested_at_typed IS NOT NULL


-- Original sale must exist
AND EXISTS (

    SELECT 1

    FROM warehouse.fact_order_item f

    WHERE f.order_item_id =
          r.order_item_id_typed
)


-- Same RAW row must not load twice
AND NOT EXISTS (

    SELECT 1

    FROM staging.stg_returns s

    WHERE s.raw_record_id =
          r.raw_record_id
);