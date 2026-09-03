-- ============================================================
-- RetailPulse
-- Cumulative Return Quantity Validation
--
-- Problem:
-- Several individually valid returns can together exceed
-- the quantity originally sold.
--
-- We consider the latest RAW version of each return_id.
-- CANCELLED returns do not consume return quantity.
-- ============================================================


WITH prepared_returns AS (

    SELECT
        r.*,

        CASE
            WHEN r.return_id IS NOT NULL
             AND BTRIM(r.return_id) <> ''
             AND pg_input_is_valid(BTRIM(r.return_id), 'bigint')
            THEN BTRIM(r.return_id)::BIGINT
        END AS return_id_typed,

        CASE
            WHEN r.order_item_id IS NOT NULL
             AND BTRIM(r.order_item_id) <> ''
             AND pg_input_is_valid(BTRIM(r.order_item_id), 'bigint')
            THEN BTRIM(r.order_item_id)::BIGINT
        END AS order_item_id_typed,

        CASE
            WHEN r.return_quantity IS NOT NULL
             AND BTRIM(r.return_quantity) <> ''
             AND pg_input_is_valid(BTRIM(r.return_quantity), 'numeric')
            THEN BTRIM(r.return_quantity)::NUMERIC
        END AS return_quantity_typed,

        CASE
            WHEN r.requested_at IS NOT NULL
             AND BTRIM(r.requested_at) <> ''
             AND pg_input_is_valid(BTRIM(r.requested_at), 'timestamptz')
            THEN BTRIM(r.requested_at)::TIMESTAMPTZ
        END AS requested_at_typed

    FROM raw.returns r
),

latest_return_versions AS (

    SELECT
        p.*,

        ROW_NUMBER() OVER (
            PARTITION BY p.return_id_typed
            ORDER BY p.raw_record_id DESC
        ) AS version_rank

    FROM prepared_returns p

    WHERE p.return_id_typed IS NOT NULL
),

valid_candidates AS (

    SELECT
        r.*

    FROM latest_return_versions r

    WHERE r.version_rank = 1

      AND r.order_item_id_typed IS NOT NULL
      AND r.return_quantity_typed IS NOT NULL
      AND r.return_quantity_typed > 0
      AND r.requested_at_typed IS NOT NULL

      -- Cancelled requests no longer consume return quantity
      AND UPPER(COALESCE(BTRIM(r.return_status), '')) <> 'CANCELLED'

      -- Ignore rows already rejected for some other reason
      AND NOT EXISTS (

          SELECT 1

          FROM audit.data_quality_issues q

          WHERE q.source_schema = 'raw'
            AND q.source_table = 'returns'
            AND q.raw_record_id = r.raw_record_id
            AND q.action = 'REJECT'
      )
),

running_returns AS (

    SELECT
        r.*,

        SUM(r.return_quantity_typed) OVER (

            PARTITION BY r.order_item_id_typed

            ORDER BY
                r.requested_at_typed,
                r.raw_record_id

            ROWS BETWEEN
                UNBOUNDED PRECEDING
                AND CURRENT ROW

        ) AS cumulative_return_quantity

    FROM valid_candidates r
),

violations AS (

    SELECT
        r.*,
        f.quantity AS sold_quantity

    FROM running_returns r

    JOIN warehouse.fact_order_item f
        ON f.order_item_id = r.order_item_id_typed

    WHERE r.cumulative_return_quantity > f.quantity
)

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
    'returns',
    v.raw_record_id,

    'return_quantity',
    'CUMULATIVE_RETURN_EXCEEDS_SOLD',

    'ERROR',
    'REJECT',

    v.return_quantity

FROM violations v

ON CONFLICT (
    source_schema,
    source_table,
    raw_record_id,
    issue_code
)
DO NOTHING;