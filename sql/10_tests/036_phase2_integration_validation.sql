-- ============================================================
-- TEST 036
-- Phase 2 Integrated Warehouse Validation
--
-- Purpose:
-- Validate Orders + Order Items + Products + Sellers +
-- Payments + Shipments + Returns together.
--
-- IMPORTANT:
-- RAW is intentionally dirty.
-- We are validating that trusted STAGING / WAREHOUSE layers
-- remain correct despite dirty source data.
-- ============================================================


DROP TABLE IF EXISTS tmp_phase2_qa_results;


CREATE TEMP TABLE tmp_phase2_qa_results (

    check_id INTEGER,

    check_name TEXT,

    failed_rows BIGINT

);



-- ============================================================
-- CHECK 1
-- No REJECTED RAW record should exist in trusted staging
-- ============================================================

INSERT INTO tmp_phase2_qa_results
SELECT
    1,

    'No REJECTED RAW rows entered staging',

    COUNT(*)

FROM (

    SELECT DISTINCT
        s.source_table,
        s.raw_record_id

    FROM (

        SELECT
            'orders' AS source_table,
            raw_record_id
        FROM staging.stg_orders

        UNION ALL

        SELECT
            'order_items',
            raw_record_id
        FROM staging.stg_order_items

        UNION ALL

        SELECT
            'products',
            raw_record_id
        FROM staging.stg_products

        UNION ALL

        SELECT
            'sellers',
            raw_record_id
        FROM staging.stg_sellers

        UNION ALL

        SELECT
            'payments',
            raw_record_id
        FROM staging.stg_payments

        UNION ALL

        SELECT
            'shipments',
            raw_record_id
        FROM staging.stg_shipments

        UNION ALL

        SELECT
            'returns',
            raw_record_id
        FROM staging.stg_returns

    ) s

    JOIN audit.data_quality_issues q

        ON q.source_schema = 'raw'
       AND q.source_table = s.source_table
       AND q.raw_record_id = s.raw_record_id
       AND q.action = 'REJECT'

) bad;



-- ============================================================
-- CHECK 2
-- No duplicate business IDs in fact tables
-- ============================================================

INSERT INTO tmp_phase2_qa_results
SELECT
    2,

    'No duplicate business IDs in facts',

    COUNT(*)

FROM (

    SELECT order_item_id::TEXT AS business_id
    FROM warehouse.fact_order_item
    GROUP BY order_item_id
    HAVING COUNT(*) > 1

    UNION ALL

    SELECT payment_id::TEXT
    FROM warehouse.fact_payment
    GROUP BY payment_id
    HAVING COUNT(*) > 1

    UNION ALL

    SELECT shipment_id::TEXT
    FROM warehouse.fact_shipment
    GROUP BY shipment_id
    HAVING COUNT(*) > 1

    UNION ALL

    SELECT return_id::TEXT
    FROM warehouse.fact_return
    GROUP BY return_id
    HAVING COUNT(*) > 1

) duplicates;



-- ============================================================
-- CHECK 3
-- Every order-item fact must have an order
-- ============================================================

INSERT INTO tmp_phase2_qa_results
SELECT
    3,

    'Every order-item fact has a parent order',

    COUNT(*)

FROM warehouse.fact_order_item f

WHERE NOT EXISTS (

    SELECT 1

    FROM staging.stg_orders_current o

    WHERE o.order_id = f.order_id

);



-- ============================================================
-- CHECK 4
-- Payments and shipments must point to real orders
-- ============================================================

INSERT INTO tmp_phase2_qa_results
SELECT
    4,

    'Payments and shipments have parent orders',

    COUNT(*)

FROM (

    SELECT p.order_id

    FROM warehouse.fact_payment p

    WHERE NOT EXISTS (

        SELECT 1

        FROM staging.stg_orders_current o

        WHERE o.order_id = p.order_id
    )


    UNION ALL


    SELECT s.order_id

    FROM warehouse.fact_shipment s

    WHERE NOT EXISTS (

        SELECT 1

        FROM staging.stg_orders_current o

        WHERE o.order_id = s.order_id
    )

) broken_parent;



-- ============================================================
-- CHECK 5
-- Fact dimension keys must resolve
--
-- FKs already protect much of this, but this is explicit QA.
-- ============================================================

INSERT INTO tmp_phase2_qa_results
SELECT
    5,

    'All fact dimension keys resolve',

    COUNT(*)

FROM (

    -- Order-item customer
    SELECT f.order_item_id

    FROM warehouse.fact_order_item f

    LEFT JOIN warehouse.dim_customer d
        ON d.customer_sk = f.customer_sk

    WHERE d.customer_sk IS NULL


    UNION ALL


    -- Order-item product
    SELECT f.order_item_id

    FROM warehouse.fact_order_item f

    LEFT JOIN warehouse.dim_product p
        ON p.product_sk = f.product_sk

    WHERE p.product_sk IS NULL


    UNION ALL


    -- Order-item seller
    SELECT f.order_item_id

    FROM warehouse.fact_order_item f

    LEFT JOIN warehouse.dim_seller s
        ON s.seller_sk = f.seller_sk

    WHERE f.seller_sk IS NOT NULL
      AND s.seller_sk IS NULL


    UNION ALL


    -- Payment customer
    SELECT p.payment_id

    FROM warehouse.fact_payment p

    LEFT JOIN warehouse.dim_customer d
        ON d.customer_sk = p.customer_sk

    WHERE d.customer_sk IS NULL


    UNION ALL


    -- Shipment customer
    SELECT s.shipment_id

    FROM warehouse.fact_shipment s

    LEFT JOIN warehouse.dim_customer d
        ON d.customer_sk = s.customer_sk

    WHERE d.customer_sk IS NULL


    UNION ALL


    -- Return customer
    SELECT r.return_id

    FROM warehouse.fact_return r

    LEFT JOIN warehouse.dim_customer d
        ON d.customer_sk = r.customer_sk

    WHERE d.customer_sk IS NULL

) missing_dimension;



-- ============================================================
-- CHECK 6
-- Order items must use customer state valid at order time
-- ============================================================

INSERT INTO tmp_phase2_qa_results
SELECT
    6,

    'Order items use correct historical customer version',

    COUNT(*)

FROM warehouse.fact_order_item f

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
          ) @> f.order_created_at

);



-- ============================================================
-- CHECK 7
-- Payments must use customer state valid at payment time
-- ============================================================

INSERT INTO tmp_phase2_qa_results
SELECT
    7,

    'Payments use correct historical customer version',

    COUNT(*)

FROM warehouse.fact_payment p

JOIN staging.stg_orders_current o
    ON o.order_id = p.order_id

WHERE NOT EXISTS (

    SELECT 1

    FROM warehouse.dim_customer c

    WHERE c.customer_sk = p.customer_sk

      AND c.customer_id = o.customer_id

      AND tstzrange(
            c.valid_from,
            c.valid_to,
            '[)'
          ) @> p.payment_created_at

);



-- ============================================================
-- CHECK 8
-- Shipments must use customer state valid at shipment time
-- ============================================================

INSERT INTO tmp_phase2_qa_results
SELECT
    8,

    'Shipments use correct historical customer version',

    COUNT(*)

FROM warehouse.fact_shipment s

JOIN staging.stg_orders_current o
    ON o.order_id = s.order_id

WHERE NOT EXISTS (

    SELECT 1

    FROM warehouse.dim_customer c

    WHERE c.customer_sk = s.customer_sk

      AND c.customer_id = o.customer_id

      AND tstzrange(
            c.valid_from,
            c.valid_to,
            '[)'
          ) @> s.shipped_at

);



-- ============================================================
-- CHECK 9
-- Return dimensional/order context must match original sale
-- ============================================================

INSERT INTO tmp_phase2_qa_results
SELECT
    9,

    'Return facts match originating order-item fact',

    COUNT(*)

FROM warehouse.fact_return r

LEFT JOIN warehouse.fact_order_item f
    ON f.order_item_id = r.order_item_id

WHERE f.order_item_id IS NULL

   OR r.order_id
        IS DISTINCT FROM f.order_id

   OR r.customer_sk
        IS DISTINCT FROM f.customer_sk

   OR r.product_sk
        IS DISTINCT FROM f.product_sk

   OR r.seller_sk
        IS DISTINCT FROM f.seller_sk;



-- ============================================================
-- CHECK 10
-- Current cumulative returns must not exceed quantity sold
-- ============================================================

INSERT INTO tmp_phase2_qa_results
SELECT
    10,

    'Cumulative return quantity does not exceed sold quantity',

    COUNT(*)

FROM (

    SELECT
        r.order_item_id

    FROM warehouse.fact_return r

    JOIN warehouse.fact_order_item f
        ON f.order_item_id = r.order_item_id

    WHERE UPPER(
        COALESCE(r.return_status, '')
    ) <> 'CANCELLED'

    GROUP BY
        r.order_item_id,
        f.quantity

    HAVING
        SUM(r.return_quantity) > f.quantity

) invalid_return_total;



-- ============================================================
-- CHECK 11
-- Order-item financial calculations remain correct
-- ============================================================

INSERT INTO tmp_phase2_qa_results
SELECT
    11,

    'Order-item gross/net calculations are correct',

    COUNT(*)

FROM warehouse.fact_order_item f

WHERE f.gross_amount
      IS DISTINCT FROM
      ROUND(
          f.quantity * f.unit_price,
          2
      )

   OR f.net_amount
      IS DISTINCT FROM
      ROUND(
          (f.quantity * f.unit_price)
          - f.discount_amount
          + f.tax_amount,
          2
      );



-- ============================================================
-- CHECK 12
-- Lifecycle timestamps make sense
-- ============================================================

INSERT INTO tmp_phase2_qa_results
SELECT
    12,

    'Shipment and return lifecycle timestamps are valid',

    COUNT(*)

FROM (

    -- DELIVERED shipment must have delivery timestamp
    SELECT shipment_id

    FROM warehouse.fact_shipment

    WHERE UPPER(
        COALESCE(shipment_status, '')
    ) = 'DELIVERED'

      AND delivered_at IS NULL


    UNION ALL


    -- Delivery cannot happen before shipment
    SELECT shipment_id

    FROM warehouse.fact_shipment

    WHERE delivered_at IS NOT NULL
      AND delivered_at < shipped_at


    UNION ALL


    -- COMPLETED return must have completion timestamp
    SELECT return_id

    FROM warehouse.fact_return

    WHERE UPPER(
        COALESCE(return_status, '')
    ) = 'COMPLETED'

      AND completed_at IS NULL


    UNION ALL


    -- Return completion cannot predate request
    SELECT return_id

    FROM warehouse.fact_return

    WHERE completed_at IS NOT NULL
      AND completed_at < requested_at

) lifecycle_error;



-- ============================================================
-- CHECK 13
-- Fact source lineage must point to actual RAW records
-- ============================================================

INSERT INTO tmp_phase2_qa_results
SELECT
    13,

    'All fact source lineage resolves to RAW',

    COUNT(*)

FROM (

    -- Order item lineage
    SELECT f.order_item_id

    FROM warehouse.fact_order_item f

    WHERE NOT EXISTS (

        SELECT 1
        FROM raw.order_items r
        WHERE r.raw_record_id =
              f.source_order_item_raw_record_id
    )

    OR NOT EXISTS (

        SELECT 1
        FROM raw.orders r
        WHERE r.raw_record_id =
              f.source_order_raw_record_id
    )


    UNION ALL


    -- Payment lineage
    SELECT p.payment_id

    FROM warehouse.fact_payment p

    WHERE NOT EXISTS (

        SELECT 1
        FROM raw.payments r
        WHERE r.raw_record_id =
              p.source_payment_raw_record_id
    )

    OR NOT EXISTS (

        SELECT 1
        FROM raw.orders r
        WHERE r.raw_record_id =
              p.source_order_raw_record_id
    )


    UNION ALL


    -- Shipment lineage
    SELECT s.shipment_id

    FROM warehouse.fact_shipment s

    WHERE NOT EXISTS (

        SELECT 1
        FROM raw.shipments r
        WHERE r.raw_record_id =
              s.source_shipment_raw_record_id
    )

    OR NOT EXISTS (

        SELECT 1
        FROM raw.orders r
        WHERE r.raw_record_id =
              s.source_order_raw_record_id
    )


    UNION ALL


    -- Return lineage
    SELECT r.return_id

    FROM warehouse.fact_return r

    WHERE NOT EXISTS (

        SELECT 1
        FROM raw.returns raw_r
        WHERE raw_r.raw_record_id =
              r.source_return_raw_record_id
    )

) broken_lineage;



-- ============================================================
-- CHECK 14
-- No warehouse fact should use a REJECTED primary source row
-- ============================================================

INSERT INTO tmp_phase2_qa_results
SELECT
    14,

    'Warehouse facts do not use REJECTED source records',

    COUNT(*)

FROM (

    SELECT
        'order_items' AS source_table,
        source_order_item_raw_record_id AS raw_record_id

    FROM warehouse.fact_order_item


    UNION ALL


    SELECT
        'payments',
        source_payment_raw_record_id

    FROM warehouse.fact_payment


    UNION ALL


    SELECT
        'shipments',
        source_shipment_raw_record_id

    FROM warehouse.fact_shipment


    UNION ALL


    SELECT
        'returns',
        source_return_raw_record_id

    FROM warehouse.fact_return

) f

JOIN audit.data_quality_issues q

    ON q.source_schema = 'raw'

   AND q.source_table = f.source_table

   AND q.raw_record_id = f.raw_record_id

   AND q.action = 'REJECT';



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

FROM tmp_phase2_qa_results

ORDER BY check_id;



-- ============================================================
-- OVERALL RESULT
-- ============================================================

SELECT

    COUNT(*) FILTER (
        WHERE failed_rows = 0
    ) AS passed_checks,

    COUNT(*) FILTER (
        WHERE failed_rows > 0
    ) AS failed_checks,

    CASE

        WHEN BOOL_AND(failed_rows = 0)
            THEN 'PHASE 2 QA PASSED'

        ELSE 'PHASE 2 QA FAILED'

    END AS overall_status

FROM tmp_phase2_qa_results;



-- ============================================================
-- INFORMATIONAL COUNTS
-- ============================================================

SELECT

    (SELECT COUNT(*)
     FROM warehouse.fact_order_item)
        AS order_item_facts,

    (SELECT COUNT(*)
     FROM warehouse.fact_payment)
        AS payment_facts,

    (SELECT COUNT(*)
     FROM warehouse.fact_shipment)
        AS shipment_facts,

    (SELECT COUNT(*)
     FROM warehouse.fact_return)
        AS return_facts;



-- ============================================================
-- INFORMATIONAL:
-- Active RAW quality issues
--
-- These do NOT automatically mean Phase 2 failed.
-- RAW intentionally contains dirty demo records.
-- ============================================================

SELECT

    source_table,

    severity,

    action,

    COUNT(*) AS active_issue_count

FROM audit.data_quality_issues

WHERE source_schema = 'raw'

  AND source_table IN (
      'orders',
      'order_items',
      'products',
      'sellers',
      'payments',
      'shipments',
      'returns'
  )

  AND resolved_at IS NULL

GROUP BY
    source_table,
    severity,
    action

ORDER BY
    source_table,
    severity,
    action;