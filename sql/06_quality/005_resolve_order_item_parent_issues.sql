-- ============================================================
-- Resolve ORDER_NOT_FOUND_YET issues
--
-- If the parent order now exists in trusted staging,
-- the old warning is no longer active.
--
-- We keep the issue for history.
-- We only mark it resolved.
-- ============================================================


UPDATE audit.data_quality_issues q

SET
    resolved_at = clock_timestamp(),

    resolution_note =
        'Parent order is now available in staging.stg_orders.'

FROM raw.order_items i

WHERE q.source_schema = 'raw'

  AND q.source_table = 'order_items'

  AND q.raw_record_id = i.raw_record_id

  AND q.issue_code = 'ORDER_NOT_FOUND_YET'

  -- only unresolved issues
  AND q.resolved_at IS NULL

  -- make sure order_id is usable
  AND i.order_id IS NOT NULL

  AND BTRIM(i.order_id) <> ''

  AND pg_input_is_valid(
        BTRIM(i.order_id),
        'bigint'
      )

  -- parent order now exists
  AND EXISTS (

      SELECT 1

      FROM staging.stg_orders o

      WHERE o.order_id =
            BTRIM(i.order_id)::BIGINT

  );