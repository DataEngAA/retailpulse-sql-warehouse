-- ============================================================
-- TEST 041
-- Phase 3 Integrated Order Consistency Validation
--
-- Goal:
-- Independently recompute one-row-per-order metrics from:
--
--   staging.stg_orders_current
--   warehouse.fact_order_item
--   warehouse.fact_payment
--   warehouse.fact_shipment
--   warehouse.fact_return
--
-- Then compare them against:
--
--   warehouse.fact_order
--
-- A successful test means the integrated fact is consistent
-- with its underlying child facts.
-- ============================================================
\set ON_ERROR_STOP on


DROP TABLE IF EXISTS tmp_expected_fact_order;
DROP TABLE IF EXISTS tmp_phase3_qa_results;



-- ============================================================
-- 1. Recompute expected order-level metrics
-- ============================================================

CREATE TEMP TABLE tmp_expected_fact_order
AS

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

        COUNT(*) AS return_request_count,

        COUNT(*) FILTER (
            WHERE UPPER(
                COALESCE(return_status, '')
            ) <> 'CANCELLED'
        ) AS active_return_count,

        COUNT(*) FILTER (
            WHERE UPPER(
                COALESCE(return_status, '')
            ) = 'COMPLETED'
        ) AS completed_return_count,

        SUM(
            CASE
                WHEN UPPER(
                    COALESCE(return_status, '')
                ) <> 'CANCELLED'
                    THEN return_quantity
                ELSE 0
            END
        ) AS active_return_quantity,

        SUM(
            CASE
                WHEN UPPER(
                    COALESCE(return_status, '')
                ) = 'COMPLETED'
                    THEN return_quantity
                ELSE 0
            END
        ) AS completed_return_quantity,

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
)


SELECT

    o.order_id,

    c.customer_sk,

    o.order_status,

    o.order_created_at,

    o.currency,


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


    COALESCE(
        o.shipping_amount,
        0
    ) AS shipping_amount,


    COALESCE(
        o.order_discount_amount,
        0
    ) AS order_discount_amount,


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


    o.raw_record_id
        AS source_order_raw_record_id


FROM staging.stg_orders_current o


JOIN warehouse.dim_customer c

    ON c.customer_id =
       o.customer_id

   AND tstzrange(

        c.valid_from,

        c.valid_to,

        '[)'

   ) @> o.order_created_at


LEFT JOIN item_metrics i
    ON i.order_id = o.order_id


LEFT JOIN payment_metrics p
    ON p.order_id = o.order_id


LEFT JOIN shipment_metrics s
    ON s.order_id = o.order_id


LEFT JOIN return_metrics r
    ON r.order_id = o.order_id;



-- ============================================================
-- 2. QA results table
-- ============================================================

CREATE TEMP TABLE tmp_phase3_qa_results (

    check_id INTEGER,

    check_name TEXT,

    failed_rows BIGINT

);



-- ============================================================
-- CHECK 1
-- Every current trusted order must exist in fact_order
-- ============================================================

INSERT INTO tmp_phase3_qa_results

SELECT

    1,

    'Every current order exists in integrated fact',

    COUNT(*)

FROM tmp_expected_fact_order e

WHERE NOT EXISTS (

    SELECT 1

    FROM warehouse.fact_order f

    WHERE f.order_id = e.order_id

);



-- ============================================================
-- CHECK 2
-- fact_order must not contain orphan orders
-- ============================================================

INSERT INTO tmp_phase3_qa_results

SELECT

    2,

    'Integrated fact contains no orphan orders',

    COUNT(*)

FROM warehouse.fact_order f

WHERE NOT EXISTS (

    SELECT 1

    FROM staging.stg_orders_current o

    WHERE o.order_id = f.order_id

);



-- ============================================================
-- CHECK 3
-- No duplicate order business IDs
-- ============================================================

INSERT INTO tmp_phase3_qa_results

SELECT

    3,

    'No duplicate order IDs in integrated fact',

    COUNT(*)

FROM (

    SELECT
        order_id

    FROM warehouse.fact_order

    GROUP BY order_id

    HAVING COUNT(*) > 1

) d;



-- ============================================================
-- CHECK 4
-- Historical customer SK must be correct
-- ============================================================

INSERT INTO tmp_phase3_qa_results

SELECT

    4,

    'Integrated orders use correct historical customer version',

    COUNT(*)

FROM warehouse.fact_order f

JOIN staging.stg_orders_current o
    ON o.order_id = f.order_id

WHERE NOT EXISTS (

    SELECT 1

    FROM warehouse.dim_customer c

    WHERE c.customer_sk = f.customer_sk

      AND c.customer_id = o.customer_id

      AND tstzrange(
            c.valid_from,
            c.valid_to,
            '[)'
          ) @> o.order_created_at

);



-- ============================================================
-- CHECK 5
-- Source order lineage must match current trusted order
-- ============================================================

INSERT INTO tmp_phase3_qa_results

SELECT

    5,

    'Integrated order lineage matches current order version',

    COUNT(*)

FROM warehouse.fact_order f

JOIN staging.stg_orders_current o
    ON o.order_id = f.order_id

WHERE f.source_order_raw_record_id
      IS DISTINCT FROM
      o.raw_record_id;



-- ============================================================
-- CHECK 6
-- Full metric comparison
-- ============================================================

INSERT INTO tmp_phase3_qa_results

SELECT

    6,

    'Integrated order metrics match underlying facts',

    COUNT(*)

FROM warehouse.fact_order f

JOIN tmp_expected_fact_order e
    ON e.order_id = f.order_id

WHERE

       f.customer_sk
           IS DISTINCT FROM e.customer_sk

    OR f.order_status
           IS DISTINCT FROM e.order_status

    OR f.order_created_at
           IS DISTINCT FROM e.order_created_at

    OR f.currency
           IS DISTINCT FROM e.currency


    OR f.item_line_count
           IS DISTINCT FROM e.item_line_count

    OR f.units_sold
           IS DISTINCT FROM e.units_sold

    OR f.item_gross_amount
           IS DISTINCT FROM e.item_gross_amount

    OR f.item_net_amount
           IS DISTINCT FROM e.item_net_amount


    OR f.shipping_amount
           IS DISTINCT FROM e.shipping_amount

    OR f.order_discount_amount
           IS DISTINCT FROM e.order_discount_amount

    OR f.expected_order_amount
           IS DISTINCT FROM e.expected_order_amount


    OR f.payment_attempt_count
           IS DISTINCT FROM e.payment_attempt_count

    OR f.successful_payment_count
           IS DISTINCT FROM e.successful_payment_count

    OR f.failed_payment_count
           IS DISTINCT FROM e.failed_payment_count

    OR f.successful_payment_amount
           IS DISTINCT FROM e.successful_payment_amount


    OR f.shipment_count
           IS DISTINCT FROM e.shipment_count

    OR f.delivered_shipment_count
           IS DISTINCT FROM e.delivered_shipment_count

    OR f.in_transit_shipment_count
           IS DISTINCT FROM e.in_transit_shipment_count

    OR f.shipped_shipment_count
           IS DISTINCT FROM e.shipped_shipment_count


    OR f.return_request_count
           IS DISTINCT FROM e.return_request_count

    OR f.active_return_count
           IS DISTINCT FROM e.active_return_count

    OR f.completed_return_count
           IS DISTINCT FROM e.completed_return_count

    OR f.active_return_quantity
           IS DISTINCT FROM e.active_return_quantity

    OR f.completed_return_quantity
           IS DISTINCT FROM e.completed_return_quantity

    OR f.completed_refund_amount
           IS DISTINCT FROM e.completed_refund_amount


    OR f.payment_vs_expected_difference
           IS DISTINCT FROM e.payment_vs_expected_difference

    OR f.net_sales_after_refunds
           IS DISTINCT FROM e.net_sales_after_refunds

    OR f.net_cash_after_refunds
           IS DISTINCT FROM e.net_cash_after_refunds;



-- ============================================================
-- CHECK 7
-- Mathematical identity:
--
-- expected =
-- item_net + shipping - order_discount
-- ============================================================

INSERT INTO tmp_phase3_qa_results

SELECT

    7,

    'Expected order amount formula is correct',

    COUNT(*)

FROM warehouse.fact_order

WHERE expected_order_amount

      IS DISTINCT FROM

      (
          item_net_amount
          +
          shipping_amount
          -
          order_discount_amount
      );



-- ============================================================
-- CHECK 8
-- Payment reconciliation formula
-- ============================================================

INSERT INTO tmp_phase3_qa_results

SELECT

    8,

    'Payment reconciliation formula is correct',

    COUNT(*)

FROM warehouse.fact_order

WHERE payment_vs_expected_difference

      IS DISTINCT FROM

      (
          successful_payment_amount
          -
          expected_order_amount
      );



-- ============================================================
-- CHECK 9
-- Net sales after refund formula
-- ============================================================

INSERT INTO tmp_phase3_qa_results

SELECT

    9,

    'Net sales after refunds formula is correct',

    COUNT(*)

FROM warehouse.fact_order

WHERE net_sales_after_refunds

      IS DISTINCT FROM

      (
          expected_order_amount
          -
          completed_refund_amount
      );



-- ============================================================
-- CHECK 10
-- Net cash after refund formula
-- ============================================================

INSERT INTO tmp_phase3_qa_results

SELECT

    10,

    'Net cash after refunds formula is correct',

    COUNT(*)

FROM warehouse.fact_order

WHERE net_cash_after_refunds

      IS DISTINCT FROM

      (
          successful_payment_amount
          -
          completed_refund_amount
      );



-- ============================================================
-- FINAL QA REPORT
-- ============================================================

SELECT

    check_id,

    check_name,

    failed_rows,

    CASE

        WHEN failed_rows = 0
            THEN 'PASS'

        ELSE 'FAIL'

    END AS status

FROM tmp_phase3_qa_results

ORDER BY check_id;



-- ============================================================
-- OVERALL PHASE 3 RESULT
-- ============================================================

SELECT

    COUNT(*) FILTER (
        WHERE failed_rows = 0
    ) AS passed_checks,

    COUNT(*) FILTER (
        WHERE failed_rows > 0
    ) AS failed_checks,

    COUNT(*) AS checks_executed,

    CASE

        WHEN COUNT(*) = 10
         AND BOOL_AND(failed_rows = 0)

            THEN 'PHASE 3 QA PASSED'

        ELSE 'PHASE 3 QA FAILED'

    END AS overall_status

FROM tmp_phase3_qa_results;


-- ============================================================
-- INFORMATIONAL
-- Show integrated order rows
-- ============================================================

SELECT

    order_id,

    order_status,

    item_line_count,

    units_sold,

    expected_order_amount,

    successful_payment_amount,

    payment_vs_expected_difference,

    shipment_count,

    delivered_shipment_count,

    return_request_count,

    completed_return_quantity,

    completed_refund_amount,

    net_sales_after_refunds,

    net_cash_after_refunds

FROM warehouse.fact_order

ORDER BY order_id;