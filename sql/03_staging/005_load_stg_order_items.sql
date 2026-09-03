-- ============================================================
-- RetailPulse
-- Load STAGING Order Items
--
-- Rules:
--
-- 1. Do not load rows with REJECT issues.
-- 2. Parent order must already exist in staging.
-- 3. Do not reload the same RAW record.
-- ============================================================


INSERT INTO staging.stg_order_items (

    raw_record_id,

    order_item_id,
    order_id,
    product_id,
    seller_id,

    quantity,
    unit_price,
    discount_amount,
    tax_amount,

    source_system,
    batch_id,
    ingested_at

)

SELECT

    i.raw_record_id,

    BTRIM(i.order_item_id)::BIGINT,

    BTRIM(i.order_id)::BIGINT,

    BTRIM(i.product_id)::BIGINT,


    -- Seller is optional
    CASE
        WHEN i.seller_id IS NOT NULL
         AND BTRIM(i.seller_id) <> ''
         AND pg_input_is_valid(
                BTRIM(i.seller_id),
                'bigint'
             )
        THEN BTRIM(i.seller_id)::BIGINT

        ELSE NULL
    END,


    BTRIM(i.quantity)::NUMERIC(18,4),

    BTRIM(i.unit_price)::NUMERIC(18,2),


    -- Optional money field
    CASE
        WHEN i.discount_amount IS NOT NULL
         AND BTRIM(i.discount_amount) <> ''
         AND pg_input_is_valid(
                BTRIM(i.discount_amount),
                'numeric'
             )
        THEN BTRIM(i.discount_amount)::NUMERIC(18,2)

        ELSE NULL
    END,


    -- Optional money field
    CASE
        WHEN i.tax_amount IS NOT NULL
         AND BTRIM(i.tax_amount) <> ''
         AND pg_input_is_valid(
                BTRIM(i.tax_amount),
                'numeric'
             )
        THEN BTRIM(i.tax_amount)::NUMERIC(18,2)

        ELSE NULL
    END,


    i.source_system,
    i.batch_id,
    i.ingested_at


FROM raw.order_items i


-- ============================================================
-- Rule 1:
-- Do not load rejected rows
-- ============================================================

WHERE NOT EXISTS (

    SELECT 1

    FROM audit.data_quality_issues q

    WHERE q.source_schema = 'raw'

      AND q.source_table = 'order_items'

      AND q.raw_record_id = i.raw_record_id

      AND q.action = 'REJECT'

)


-- ============================================================
-- Rule 2:
-- Parent order must already be trusted enough
-- to exist in staging.
-- ============================================================

AND EXISTS (

    SELECT 1

    FROM staging.stg_orders o

    WHERE o.order_id =
          BTRIM(i.order_id)::BIGINT

)


-- ============================================================
-- Rule 3:
-- Same RAW record should not load twice
-- ============================================================

AND NOT EXISTS (

    SELECT 1

    FROM staging.stg_order_items s

    WHERE s.raw_record_id =
          i.raw_record_id

);