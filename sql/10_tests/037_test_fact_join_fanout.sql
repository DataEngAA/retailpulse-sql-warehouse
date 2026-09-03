-- ============================================================
-- TEST 037
-- Phase 3
-- Demonstrate FACT-TO-FACT FANOUT
--
-- Different fact tables have different grains.
-- Direct joins can multiply rows and financial values.
-- ============================================================


-- ============================================================
-- 1. Correct order-item totals by themselves
-- ============================================================

SELECT
    order_id,

    COUNT(*) AS item_rows,

    SUM(gross_amount) AS gross_amount,

    SUM(net_amount) AS net_amount

FROM warehouse.fact_order_item

GROUP BY order_id

ORDER BY order_id;



-- ============================================================
-- 2. Correct payment totals by themselves
-- ============================================================

SELECT
    order_id,

    COUNT(*) AS payment_rows,

    SUM(payment_amount) AS all_payment_amount,

    SUM(
        CASE
            WHEN UPPER(payment_status) = 'SUCCESS'
                THEN payment_amount
            ELSE 0
        END
    ) AS successful_payment_amount

FROM warehouse.fact_payment

GROUP BY order_id

ORDER BY order_id;



-- ============================================================
-- 3. Now join order items directly to payments
--
-- This is intentionally WRONG.
-- We are demonstrating fanout.
-- ============================================================

SELECT
    i.order_id,

    COUNT(*) AS joined_rows,

    SUM(i.gross_amount) AS wrong_gross_amount,

    SUM(i.net_amount) AS wrong_net_amount,

    SUM(
        CASE
            WHEN UPPER(p.payment_status) = 'SUCCESS'
                THEN p.payment_amount
            ELSE 0
        END
    ) AS wrong_successful_payment_amount

FROM warehouse.fact_order_item i

JOIN warehouse.fact_payment p
    ON p.order_id = i.order_id

GROUP BY i.order_id

ORDER BY i.order_id;



-- ============================================================
-- 4. Show exactly how many rows each fact contributes
-- ============================================================

SELECT

    o.order_id,

    COALESCE(i.item_count, 0)
        AS item_count,

    COALESCE(p.payment_count, 0)
        AS payment_count,

    COALESCE(s.shipment_count, 0)
        AS shipment_count,

    COALESCE(r.return_count, 0)
        AS return_count

FROM staging.stg_orders_current o

LEFT JOIN (

    SELECT
        order_id,
        COUNT(*) AS item_count

    FROM warehouse.fact_order_item

    GROUP BY order_id

) i
    ON i.order_id = o.order_id

LEFT JOIN (

    SELECT
        order_id,
        COUNT(*) AS payment_count

    FROM warehouse.fact_payment

    GROUP BY order_id

) p
    ON p.order_id = o.order_id

LEFT JOIN (

    SELECT
        order_id,
        COUNT(*) AS shipment_count

    FROM warehouse.fact_shipment

    GROUP BY order_id

) s
    ON s.order_id = o.order_id

LEFT JOIN (

    SELECT
        order_id,
        COUNT(*) AS return_count

    FROM warehouse.fact_return

    GROUP BY order_id

) r
    ON r.order_id = o.order_id

ORDER BY o.order_id;