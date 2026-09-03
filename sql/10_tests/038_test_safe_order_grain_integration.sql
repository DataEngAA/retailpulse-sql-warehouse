-- ============================================================
-- TEST 038
-- Safe Integrated Fact Query
--
-- Solution to fact-to-fact fanout:
--
-- 1. Aggregate every fact independently
-- 2. Bring each one to ONE ROW PER ORDER
-- 3. Join those order-grain datasets
-- ============================================================


WITH item_metrics AS (

    SELECT
        order_id,

        COUNT(*) AS item_line_count,

        SUM(quantity) AS units_sold,

        SUM(gross_amount) AS gross_amount,

        SUM(net_amount) AS net_amount

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


shipment_metrics AS (

    SELECT
        order_id,

        COUNT(*) AS shipment_count,

        COUNT(*) FILTER (
            WHERE UPPER(shipment_status) = 'DELIVERED'
        ) AS delivered_shipment_count,

        COUNT(*) FILTER (
            WHERE UPPER(shipment_status) = 'IN_TRANSIT'
        ) AS in_transit_shipment_count,

        COUNT(*) FILTER (
            WHERE UPPER(shipment_status) = 'SHIPPED'
        ) AS shipped_shipment_count

    FROM warehouse.fact_shipment

    GROUP BY order_id

),


return_metrics AS (

    SELECT
        order_id,

        COUNT(*) AS return_count,

        SUM(
            CASE
                WHEN UPPER(return_status) <> 'CANCELLED'
                    THEN return_quantity
                ELSE 0
            END
        ) AS returned_quantity,

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

    o.customer_id,

    o.order_status,

    o.order_created_at,

    o.currency,


    -- SALES
    COALESCE(i.item_line_count, 0)
        AS item_line_count,

    COALESCE(i.units_sold, 0)
        AS units_sold,

    COALESCE(i.gross_amount, 0)
        AS gross_amount,

    COALESCE(i.net_amount, 0)
        AS net_amount,


    -- PAYMENTS
    COALESCE(p.payment_attempt_count, 0)
        AS payment_attempt_count,

    COALESCE(p.successful_payment_count, 0)
        AS successful_payment_count,

    COALESCE(p.failed_payment_count, 0)
        AS failed_payment_count,

    COALESCE(p.successful_payment_amount, 0)
        AS successful_payment_amount,


    -- SHIPMENTS
    COALESCE(s.shipment_count, 0)
        AS shipment_count,

    COALESCE(s.delivered_shipment_count, 0)
        AS delivered_shipment_count,

    COALESCE(s.in_transit_shipment_count, 0)
        AS in_transit_shipment_count,

    COALESCE(s.shipped_shipment_count, 0)
        AS shipped_shipment_count,


    -- RETURNS
    COALESCE(r.return_count, 0)
        AS return_count,

    COALESCE(r.returned_quantity, 0)
        AS returned_quantity,

    COALESCE(r.completed_refund_amount, 0)
        AS completed_refund_amount,


    -- RECONCILIATION
    COALESCE(p.successful_payment_amount, 0)
    -
    COALESCE(i.net_amount, 0)
        AS payment_vs_sales_difference


FROM staging.stg_orders_current o


LEFT JOIN item_metrics i
    ON i.order_id = o.order_id


LEFT JOIN payment_metrics p
    ON p.order_id = o.order_id


LEFT JOIN shipment_metrics s
    ON s.order_id = o.order_id


LEFT JOIN return_metrics r
    ON r.order_id = o.order_id


ORDER BY o.order_id;