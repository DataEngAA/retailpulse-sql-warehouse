-- ============================================================
-- TEST 039
-- Phase 3 Financial Reconciliation
--
-- Goal:
-- Build the correct order-level financial meaning before
-- creating the permanent integrated order fact.
-- ============================================================


WITH item_metrics AS (

    SELECT
        order_id,

        COUNT(*) AS item_line_count,

        SUM(quantity) AS units_sold,

        SUM(gross_amount) AS item_gross_amount,

        SUM(net_amount) AS item_net_amount

    FROM warehouse.fact_order_item

    GROUP BY order_id
),


payment_metrics AS (

    SELECT
        order_id,

        COUNT(*) AS payment_attempt_count,

        COUNT(*) FILTER (
            WHERE UPPER(payment_status) = 'SUCCESS'
        ) AS successful_payment_count,

        COUNT(*) FILTER (
            WHERE UPPER(payment_status) = 'FAILED'
        ) AS failed_payment_count,

        SUM(
            CASE
                WHEN UPPER(payment_status) = 'SUCCESS'
                    THEN payment_amount
                ELSE 0
            END
        ) AS successful_payment_amount

    FROM warehouse.fact_payment

    GROUP BY order_id
),


return_metrics AS (

    SELECT
        order_id,

        COUNT(*) AS return_request_count,

        COUNT(*) FILTER (
            WHERE UPPER(return_status) <> 'CANCELLED'
        ) AS active_return_count,

        COUNT(*) FILTER (
            WHERE UPPER(return_status) = 'COMPLETED'
        ) AS completed_return_count,


        SUM(
            CASE
                WHEN UPPER(return_status) <> 'CANCELLED'
                    THEN return_quantity
                ELSE 0
            END
        ) AS active_return_quantity,


        SUM(
            CASE
                WHEN UPPER(return_status) = 'COMPLETED'
                    THEN return_quantity
                ELSE 0
            END
        ) AS completed_return_quantity,


        SUM(
            CASE
                WHEN UPPER(return_status) = 'COMPLETED'
                    THEN refund_amount
                ELSE 0
            END
        ) AS completed_refund_amount

    FROM warehouse.fact_return

    GROUP BY order_id
)


SELECT

    o.order_id,

    o.order_status,

    o.currency,


    -- ========================================================
    -- SALES
    -- ========================================================

    COALESCE(i.item_line_count, 0)
        AS item_line_count,

    COALESCE(i.units_sold, 0)
        AS units_sold,

    COALESCE(i.item_gross_amount, 0)
        AS item_gross_amount,

    COALESCE(i.item_net_amount, 0)
        AS item_net_amount,


    -- Order-level financial adjustments
    COALESCE(o.shipping_amount, 0)
        AS shipping_amount,

    COALESCE(o.order_discount_amount, 0)
        AS order_discount_amount,


    -- Expected amount for the complete order
    (
        COALESCE(i.item_net_amount, 0)
        +
        COALESCE(o.shipping_amount, 0)
        -
        COALESCE(o.order_discount_amount, 0)
    ) AS expected_order_amount,


    -- ========================================================
    -- PAYMENTS
    -- ========================================================

    COALESCE(p.payment_attempt_count, 0)
        AS payment_attempt_count,

    COALESCE(p.successful_payment_count, 0)
        AS successful_payment_count,

    COALESCE(p.failed_payment_count, 0)
        AS failed_payment_count,

    COALESCE(p.successful_payment_amount, 0)
        AS successful_payment_amount,


    -- ========================================================
    -- RETURNS
    -- ========================================================

    COALESCE(r.return_request_count, 0)
        AS return_request_count,

    COALESCE(r.active_return_count, 0)
        AS active_return_count,

    COALESCE(r.completed_return_count, 0)
        AS completed_return_count,

    COALESCE(r.active_return_quantity, 0)
        AS active_return_quantity,

    COALESCE(r.completed_return_quantity, 0)
        AS completed_return_quantity,

    COALESCE(r.completed_refund_amount, 0)
        AS completed_refund_amount,


    -- ========================================================
    -- RECONCILIATION
    -- ========================================================

    COALESCE(p.successful_payment_amount, 0)
    -
    (
        COALESCE(i.item_net_amount, 0)
        +
        COALESCE(o.shipping_amount, 0)
        -
        COALESCE(o.order_discount_amount, 0)
    )
        AS payment_vs_expected_difference,


    -- Sales value remaining after completed returns
    (
        COALESCE(i.item_net_amount, 0)
        +
        COALESCE(o.shipping_amount, 0)
        -
        COALESCE(o.order_discount_amount, 0)
        -
        COALESCE(r.completed_refund_amount, 0)
    )
        AS net_sales_after_refunds,


    -- Actual collected cash remaining after refunds
    (
        COALESCE(p.successful_payment_amount, 0)
        -
        COALESCE(r.completed_refund_amount, 0)
    )
        AS net_cash_after_refunds


FROM staging.stg_orders_current o

LEFT JOIN item_metrics i
    ON i.order_id = o.order_id

LEFT JOIN payment_metrics p
    ON p.order_id = o.order_id

LEFT JOIN return_metrics r
    ON r.order_id = o.order_id

ORDER BY o.order_id;