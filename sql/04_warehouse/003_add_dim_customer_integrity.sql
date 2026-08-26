-- ============================================================
-- Customer dimension integrity protections
-- Run once after warehouse.dim_customer has been created.
-- ============================================================


-- Required so GiST can compare BIGINT customer_id values
CREATE EXTENSION IF NOT EXISTS btree_gist;


-- A customer may have only one current warehouse version
CREATE UNIQUE INDEX IF NOT EXISTS ux_dim_customer_one_current
ON warehouse.dim_customer (customer_id)
WHERE is_current = TRUE;


-- Historical validity periods for the same customer
-- must never overlap.
--
-- '[)' means:
-- valid_from is inclusive
-- valid_to   is exclusive
ALTER TABLE warehouse.dim_customer
ADD CONSTRAINT ex_dim_customer_no_overlap
EXCLUDE USING gist (
    customer_id WITH =,
    tstzrange(valid_from, valid_to, '[)') WITH &&
);