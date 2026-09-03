-- ============================================================
-- RetailPulse
-- Load STAGING Payments
--
-- Important:
-- Never directly cast untrusted RAW values.
-- Convert only after validating the value.
-- ============================================================


WITH prepared_payments AS (

    SELECT

        p.*,


        -- Safe payment_id conversion
        CASE
            WHEN p.payment_id IS NOT NULL
             AND BTRIM(p.payment_id) <> ''
             AND pg_input_is_valid(
                    BTRIM(p.payment_id),
                    'bigint'
                 )
            THEN BTRIM(p.payment_id)::BIGINT

            ELSE NULL
        END AS payment_id_typed,


        -- Safe order_id conversion
        CASE
            WHEN p.order_id IS NOT NULL
             AND BTRIM(p.order_id) <> ''
             AND pg_input_is_valid(
                    BTRIM(p.order_id),
                    'bigint'
                 )
            THEN BTRIM(p.order_id)::BIGINT

            ELSE NULL
        END AS order_id_typed,


        -- Safe payment amount conversion
        CASE
            WHEN p.payment_amount IS NOT NULL
             AND BTRIM(p.payment_amount) <> ''
             AND pg_input_is_valid(
                    BTRIM(p.payment_amount),
                    'numeric'
                 )
            THEN BTRIM(p.payment_amount)::NUMERIC(18,2)

            ELSE NULL
        END AS payment_amount_typed,


        -- Safe timestamp conversion
        CASE
            WHEN p.payment_created_at IS NOT NULL
             AND BTRIM(p.payment_created_at) <> ''
             AND pg_input_is_valid(
                    BTRIM(p.payment_created_at),
                    'timestamptz'
                 )
            THEN BTRIM(p.payment_created_at)::TIMESTAMPTZ

            ELSE NULL
        END AS payment_created_at_typed


    FROM raw.payments p

)


INSERT INTO staging.stg_payments (

    raw_record_id,

    payment_id,
    order_id,

    payment_type,
    payment_status,
    payment_method,

    payment_amount,
    currency,

    payment_created_at,

    transaction_reference,

    source_system,
    batch_id,
    ingested_at

)

SELECT

    p.raw_record_id,

    p.payment_id_typed,

    p.order_id_typed,

    UPPER(NULLIF(BTRIM(p.payment_type), '')),

    UPPER(NULLIF(BTRIM(p.payment_status), '')),

    UPPER(NULLIF(BTRIM(p.payment_method), '')),

    p.payment_amount_typed,

    UPPER(NULLIF(BTRIM(p.currency), '')),

    p.payment_created_at_typed,

    NULLIF(BTRIM(p.transaction_reference), ''),

    p.source_system,

    p.batch_id,

    p.ingested_at


FROM prepared_payments p


-- ============================================================
-- Rule 1:
-- No REJECT quality issue
-- ============================================================

WHERE NOT EXISTS (

    SELECT 1

    FROM audit.data_quality_issues q

    WHERE q.source_schema = 'raw'

      AND q.source_table = 'payments'

      AND q.raw_record_id = p.raw_record_id

      AND q.action = 'REJECT'

)


-- ============================================================
-- Defensive validation
--
-- Even if quality detection was accidentally skipped,
-- unsafe required values still cannot enter staging.
-- ============================================================

AND p.payment_id_typed IS NOT NULL

AND p.order_id_typed IS NOT NULL

AND p.payment_amount_typed IS NOT NULL

AND p.payment_created_at_typed IS NOT NULL


-- ============================================================
-- Rule 2:
-- Parent order must exist
-- ============================================================

AND EXISTS (

    SELECT 1

    FROM staging.stg_orders_current o

    WHERE o.order_id =
          p.order_id_typed

)


-- ============================================================
-- Rule 3:
-- Do not load same RAW row twice
-- ============================================================

AND NOT EXISTS (

    SELECT 1

    FROM staging.stg_payments s

    WHERE s.raw_record_id =
          p.raw_record_id

);