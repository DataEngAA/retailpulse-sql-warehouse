-- ============================================================
-- RetailPulse
-- Integrated Order Fact Loader
--
-- Target grain:
--     one row = one order
--
-- IMPORTANT:
-- Child fact tables have different grains.
--
-- Therefore:
--
-- fact_order_item
--      ↓ aggregate
-- one row per order
--
-- fact_payment
--      ↓ aggregate
-- one row per order
--
-- fact_shipment
--      ↓ aggregate
-- one row per order
--
-- fact_return
--      ↓ aggregate
-- one row per order
--
-- Only AFTER aggregation are the datasets joined.
--
-- This prevents fact-to-fact fanout.
-- ============================================================



-- ============================================================
-- 1. Aggregate ORDER ITEM facts
-- ============================================================

WITH item_metrics AS (

    SELECT

        order_id,

        COUNT(*)
            AS item_line_count,

        SUM(quantity)
            AS units_sold,

        SUM(gross_amount)
            AS item_gross_amount,

        SUM(net_amount)
            AS item_net_amount

    FROM warehouse.fact_order_item

    GROUP BY order_id

),



-- ============================================================
-- 2. Aggregate PAYMENT facts
-- ============================================================

payment_metrics AS (

    SELECT

        order_id,

        COUNT(*)
            AS payment_attempt_count,


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



-- ============================================================
-- 3. Aggregate SHIPMENT facts
-- ============================================================

shipment_metrics AS (

    SELECT

        order_id,

        COUNT(*)
            AS shipment_count,


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



-- ============================================================
-- 4. Aggregate RETURN facts
-- ============================================================

return_metrics AS (

    SELECT

        order_id,


        -- All return requests
        COUNT(*)
            AS return_request_count,


        -- Anything not cancelled
        COUNT(*) FILTER (

            WHERE UPPER(
                COALESCE(return_status, '')
            ) <> 'CANCELLED'

        ) AS active_return_count,


        -- Actually completed returns
        COUNT(*) FILTER (

            WHERE UPPER(
                COALESCE(return_status, '')
            ) = 'COMPLETED'

        ) AS completed_return_count,


        -- Quantity currently involved in non-cancelled returns
        SUM(

            CASE

                WHEN UPPER(
                    COALESCE(return_status, '')
                ) <> 'CANCELLED'

                    THEN return_quantity

                ELSE 0

            END

        ) AS active_return_quantity,


        -- Quantity actually completed
        SUM(

            CASE

                WHEN UPPER(
                    COALESCE(return_status, '')
                ) = 'COMPLETED'

                    THEN return_quantity

                ELSE 0

            END

        ) AS completed_return_quantity,


        -- Refund amount from completed returns only
        SUM(

            CASE

                WHEN UPPER(
                    COALESCE(return_status, '')
                ) = 'COMPLETED'

                    THEN refund_amount

                ELSE 0

            END

        ) AS completed_refund_amount

    FROM warehouse.fact_return

    GROUP BY order_id

),



-- ============================================================
-- 5. Build one integrated row per order
-- ============================================================

integrated_orders AS (

    SELECT

        -- ====================================================
        -- ORDER IDENTITY
        -- ====================================================

        o.order_id,

        c.customer_sk,

        o.order_status,

        o.order_created_at,

        o.currency,



        -- ====================================================
        -- SALES / ITEM METRICS
        -- ====================================================

        COALESCE(
            i.item_line_count,
            0
        ) AS item_line_count,


        COALESCE(
            i.units_sold,
            0
        ) AS units_sold,


        COALESCE(
            i.item_gross_amount,
            0
        ) AS item_gross_amount,


        COALESCE(
            i.item_net_amount,
            0
        ) AS item_net_amount,



        -- ====================================================
        -- ORDER-LEVEL FINANCIALS
        --
        -- These intentionally live at order grain.
        -- We did NOT repeat them on each order-item row.
        -- ====================================================

        COALESCE(
            o.shipping_amount,
            0
        ) AS shipping_amount,


        COALESCE(
            o.order_discount_amount,
            0
        ) AS order_discount_amount,



        -- Expected total amount of the order:
        --
        -- item net
        -- + shipping
        -- - order-level discount
        (
            COALESCE(
                i.item_net_amount,
                0
            )

            +

            COALESCE(
                o.shipping_amount,
                0
            )

            -

            COALESCE(
                o.order_discount_amount,
                0
            )

        ) AS expected_order_amount,



        -- ====================================================
        -- PAYMENT METRICS
        -- ====================================================

        COALESCE(
            p.payment_attempt_count,
            0
        ) AS payment_attempt_count,


        COALESCE(
            p.successful_payment_count,
            0
        ) AS successful_payment_count,


        COALESCE(
            p.failed_payment_count,
            0
        ) AS failed_payment_count,


        COALESCE(
            p.successful_payment_amount,
            0
        ) AS successful_payment_amount,



        -- ====================================================
        -- SHIPMENT METRICS
        -- ====================================================

        COALESCE(
            s.shipment_count,
            0
        ) AS shipment_count,


        COALESCE(
            s.delivered_shipment_count,
            0
        ) AS delivered_shipment_count,


        COALESCE(
            s.in_transit_shipment_count,
            0
        ) AS in_transit_shipment_count,


        COALESCE(
            s.shipped_shipment_count,
            0
        ) AS shipped_shipment_count,



        -- ====================================================
        -- RETURN METRICS
        -- ====================================================

        COALESCE(
            r.return_request_count,
            0
        ) AS return_request_count,


        COALESCE(
            r.active_return_count,
            0
        ) AS active_return_count,


        COALESCE(
            r.completed_return_count,
            0
        ) AS completed_return_count,


        COALESCE(
            r.active_return_quantity,
            0
        ) AS active_return_quantity,


        COALESCE(
            r.completed_return_quantity,
            0
        ) AS completed_return_quantity,


        COALESCE(
            r.completed_refund_amount,
            0
        ) AS completed_refund_amount,



        -- ====================================================
        -- PAYMENT RECONCILIATION
        --
        -- Positive:
        --     paid more than expected
        --
        -- Zero:
        --     perfectly reconciled
        --
        -- Negative:
        --     paid less than expected
        -- ====================================================

        (
            COALESCE(
                p.successful_payment_amount,
                0
            )

            -

            (
                COALESCE(
                    i.item_net_amount,
                    0
                )

                +

                COALESCE(
                    o.shipping_amount,
                    0
                )

                -

                COALESCE(
                    o.order_discount_amount,
                    0
                )
            )

        ) AS payment_vs_expected_difference,



        -- ====================================================
        -- SALES AFTER COMPLETED REFUNDS
        -- ====================================================

        (
            COALESCE(
                i.item_net_amount,
                0
            )

            +

            COALESCE(
                o.shipping_amount,
                0
            )

            -

            COALESCE(
                o.order_discount_amount,
                0
            )

            -

            COALESCE(
                r.completed_refund_amount,
                0
            )

        ) AS net_sales_after_refunds,



        -- ====================================================
        -- CASH AFTER COMPLETED REFUNDS
        -- ====================================================

        (
            COALESCE(
                p.successful_payment_amount,
                0
            )

            -

            COALESCE(
                r.completed_refund_amount,
                0
            )

        ) AS net_cash_after_refunds,



        -- ====================================================
        -- LINEAGE
        -- ====================================================

        o.raw_record_id
            AS source_order_raw_record_id


    FROM staging.stg_orders_current o



    -- ========================================================
    -- Historical customer lookup
    --
    -- We want the customer dimension version that was valid
    -- when the order happened.
    -- ========================================================

    JOIN warehouse.dim_customer c

        ON c.customer_id =
           o.customer_id

       AND tstzrange(

            c.valid_from,

            c.valid_to,

            '[)'

       ) @> o.order_created_at



    -- ========================================================
    -- Safe order-grain joins
    -- ========================================================

    LEFT JOIN item_metrics i

        ON i.order_id =
           o.order_id


    LEFT JOIN payment_metrics p

        ON p.order_id =
           o.order_id


    LEFT JOIN shipment_metrics s

        ON s.order_id =
           o.order_id


    LEFT JOIN return_metrics r

        ON r.order_id =
           o.order_id

)



-- ============================================================
-- 6. Load integrated order fact
-- ============================================================

INSERT INTO warehouse.fact_order (

    order_id,

    customer_sk,

    order_status,

    order_created_at,

    currency,


    item_line_count,

    units_sold,

    item_gross_amount,

    item_net_amount,


    shipping_amount,

    order_discount_amount,

    expected_order_amount,


    payment_attempt_count,

    successful_payment_count,

    failed_payment_count,

    successful_payment_amount,


    shipment_count,

    delivered_shipment_count,

    in_transit_shipment_count,

    shipped_shipment_count,


    return_request_count,

    active_return_count,

    completed_return_count,

    active_return_quantity,

    completed_return_quantity,

    completed_refund_amount,


    payment_vs_expected_difference,

    net_sales_after_refunds,

    net_cash_after_refunds,


    source_order_raw_record_id

)



SELECT

    order_id,

    customer_sk,

    order_status,

    order_created_at,

    currency,


    item_line_count,

    units_sold,

    item_gross_amount,

    item_net_amount,


    shipping_amount,

    order_discount_amount,

    expected_order_amount,


    payment_attempt_count,

    successful_payment_count,

    failed_payment_count,

    successful_payment_amount,


    shipment_count,

    delivered_shipment_count,

    in_transit_shipment_count,

    shipped_shipment_count,


    return_request_count,

    active_return_count,

    completed_return_count,

    active_return_quantity,

    completed_return_quantity,

    completed_refund_amount,


    payment_vs_expected_difference,

    net_sales_after_refunds,

    net_cash_after_refunds,


    source_order_raw_record_id


FROM integrated_orders



-- ============================================================
-- 7. Existing order?
--
-- Update the same integrated order row.
-- ============================================================

ON CONFLICT (order_id)

DO UPDATE SET


    customer_sk =
        EXCLUDED.customer_sk,


    order_status =
        EXCLUDED.order_status,


    order_created_at =
        EXCLUDED.order_created_at,


    currency =
        EXCLUDED.currency,



    item_line_count =
        EXCLUDED.item_line_count,


    units_sold =
        EXCLUDED.units_sold,


    item_gross_amount =
        EXCLUDED.item_gross_amount,


    item_net_amount =
        EXCLUDED.item_net_amount,



    shipping_amount =
        EXCLUDED.shipping_amount,


    order_discount_amount =
        EXCLUDED.order_discount_amount,


    expected_order_amount =
        EXCLUDED.expected_order_amount,



    payment_attempt_count =
        EXCLUDED.payment_attempt_count,


    successful_payment_count =
        EXCLUDED.successful_payment_count,


    failed_payment_count =
        EXCLUDED.failed_payment_count,


    successful_payment_amount =
        EXCLUDED.successful_payment_amount,



    shipment_count =
        EXCLUDED.shipment_count,


    delivered_shipment_count =
        EXCLUDED.delivered_shipment_count,


    in_transit_shipment_count =
        EXCLUDED.in_transit_shipment_count,


    shipped_shipment_count =
        EXCLUDED.shipped_shipment_count,



    return_request_count =
        EXCLUDED.return_request_count,


    active_return_count =
        EXCLUDED.active_return_count,


    completed_return_count =
        EXCLUDED.completed_return_count,


    active_return_quantity =
        EXCLUDED.active_return_quantity,


    completed_return_quantity =
        EXCLUDED.completed_return_quantity,


    completed_refund_amount =
        EXCLUDED.completed_refund_amount,



    payment_vs_expected_difference =
        EXCLUDED.payment_vs_expected_difference,


    net_sales_after_refunds =
        EXCLUDED.net_sales_after_refunds,


    net_cash_after_refunds =
        EXCLUDED.net_cash_after_refunds,



    source_order_raw_record_id =
        EXCLUDED.source_order_raw_record_id,


    -- Only refreshed when an actual change occurs because
    -- the WHERE clause below prevents unnecessary updates.
    loaded_at =
        clock_timestamp()



-- ============================================================
-- 8. Change detection
--
-- Explicit column-to-column comparison is intentional.
--
-- This is safer than:
--
--     (a,b,c) IS DISTINCT FROM (x,y,z)
--
-- because positional tuples can accidentally become
-- misaligned when new columns are added.
-- ============================================================

WHERE

       warehouse.fact_order.customer_sk
           IS DISTINCT FROM
           EXCLUDED.customer_sk


    OR warehouse.fact_order.order_status
           IS DISTINCT FROM
           EXCLUDED.order_status


    OR warehouse.fact_order.order_created_at
           IS DISTINCT FROM
           EXCLUDED.order_created_at


    OR warehouse.fact_order.currency
           IS DISTINCT FROM
           EXCLUDED.currency



    OR warehouse.fact_order.item_line_count
           IS DISTINCT FROM
           EXCLUDED.item_line_count


    OR warehouse.fact_order.units_sold
           IS DISTINCT FROM
           EXCLUDED.units_sold


    OR warehouse.fact_order.item_gross_amount
           IS DISTINCT FROM
           EXCLUDED.item_gross_amount


    OR warehouse.fact_order.item_net_amount
           IS DISTINCT FROM
           EXCLUDED.item_net_amount



    OR warehouse.fact_order.shipping_amount
           IS DISTINCT FROM
           EXCLUDED.shipping_amount


    OR warehouse.fact_order.order_discount_amount
           IS DISTINCT FROM
           EXCLUDED.order_discount_amount


    OR warehouse.fact_order.expected_order_amount
           IS DISTINCT FROM
           EXCLUDED.expected_order_amount



    OR warehouse.fact_order.payment_attempt_count
           IS DISTINCT FROM
           EXCLUDED.payment_attempt_count


    OR warehouse.fact_order.successful_payment_count
           IS DISTINCT FROM
           EXCLUDED.successful_payment_count


    OR warehouse.fact_order.failed_payment_count
           IS DISTINCT FROM
           EXCLUDED.failed_payment_count


    OR warehouse.fact_order.successful_payment_amount
           IS DISTINCT FROM
           EXCLUDED.successful_payment_amount



    OR warehouse.fact_order.shipment_count
           IS DISTINCT FROM
           EXCLUDED.shipment_count


    OR warehouse.fact_order.delivered_shipment_count
           IS DISTINCT FROM
           EXCLUDED.delivered_shipment_count


    OR warehouse.fact_order.in_transit_shipment_count
           IS DISTINCT FROM
           EXCLUDED.in_transit_shipment_count


    OR warehouse.fact_order.shipped_shipment_count
           IS DISTINCT FROM
           EXCLUDED.shipped_shipment_count



    OR warehouse.fact_order.return_request_count
           IS DISTINCT FROM
           EXCLUDED.return_request_count


    OR warehouse.fact_order.active_return_count
           IS DISTINCT FROM
           EXCLUDED.active_return_count


    OR warehouse.fact_order.completed_return_count
           IS DISTINCT FROM
           EXCLUDED.completed_return_count


    OR warehouse.fact_order.active_return_quantity
           IS DISTINCT FROM
           EXCLUDED.active_return_quantity


    OR warehouse.fact_order.completed_return_quantity
           IS DISTINCT FROM
           EXCLUDED.completed_return_quantity


    OR warehouse.fact_order.completed_refund_amount
           IS DISTINCT FROM
           EXCLUDED.completed_refund_amount



    OR warehouse.fact_order.payment_vs_expected_difference
           IS DISTINCT FROM
           EXCLUDED.payment_vs_expected_difference


    OR warehouse.fact_order.net_sales_after_refunds
           IS DISTINCT FROM
           EXCLUDED.net_sales_after_refunds


    OR warehouse.fact_order.net_cash_after_refunds
           IS DISTINCT FROM
           EXCLUDED.net_cash_after_refunds



    OR warehouse.fact_order.source_order_raw_record_id
           IS DISTINCT FROM
           EXCLUDED.source_order_raw_record_id;