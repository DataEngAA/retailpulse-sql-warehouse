# RetailPulse SQL Warehouse — MEMORY

> Purpose: keep a durable record of architecture decisions, problems we hit, why they happened, and how we fixed them.
>
> Update this file whenever we make a meaningful design decision, hit a non-obvious failure, or change an ETL contract.

---

## 1. Project Goal

**RetailPulse SQL Warehouse** is a SQL-first Data Engineering project built entirely in PostgreSQL.

Primary goal:

- learn SQL deeply from a Data Engineering perspective
- design a realistic warehouse instead of only solving isolated SQL questions
- build incremental ETL, dimensional models, SCD handling, data quality, controls, and performance patterns
- keep the center of the project on SQL

### Current stack

- PostgreSQL 18
- SQL / PostgreSQL features
- No Python in V1/V2
- Local development on Windows
- Git + GitHub for version control

---

## 2. Current Architecture

```text
Source-like records
      |
      v
raw
      |
      +--> audit.data_quality_issues
      |
      v
staging.stg_customer_versions
      |
      +--> staging.stg_customers_current
      |
      v
warehouse.dim_customer
      |
      v
mart (future)
```

Supporting schemas:

```text
raw        -> preserve source truth
staging    -> cleaned, typed, usable data
warehouse  -> dimensional/history model
mart       -> business-facing datasets
audit      -> data-quality and run issues
control    -> pipeline state / watermarks
```

---

## 3. Core Architecture Decisions

### Decision: RAW is permissive

**Issue**

Source data can contain malformed IDs, bad timestamps, bad emails, blanks, and repeated customer versions.

**Reason**

If RAW is too strict, bad source data is rejected before we can inspect, audit, or recover it.

**Decision**

Store most source fields as `TEXT`.

Keep only pipeline-controlled metadata strict:

- `source_system`
- `batch_id`
- `ingested_at`

Use a technical identity primary key:

```text
raw_record_id
```

Do not use `customer_id` as the RAW primary key.

**Why**

A source customer can legitimately appear many times because RAW stores versions/events, not one canonical entity row.

---

### Decision: Identity problems reject the record; attribute problems do not

Rule:

```text
Identity problem -> reject whole entity version
Attribute problem -> clean / nullify / flag / fallback
```

Examples:

```text
customer_id missing      -> REJECT
customer_id non-numeric  -> REJECT
invalid email            -> NULLIFY / WARNING
missing city             -> FLAG
bad updated_at           -> FALLBACK
```

This prevents one bad attribute from destroying an otherwise usable customer record.

---

### Decision: Effective timestamp has fallback logic

Priority:

```text
valid updated_at
      ->
valid created_at
      ->
ingested_at
```

`timestamp_source` records which value was selected.

**Reason**

Source timestamps are not always reliable, but warehouse history still needs a deterministic effective time.

---

### Decision: Preserve full staging history

Physical table:

```text
staging.stg_customer_versions
```

One usable RAW version becomes one staging version.

A separate view:

```text
staging.stg_customers_current
```

returns only the latest version per customer using:

```sql
ROW_NUMBER() OVER (
    PARTITION BY customer_id
    ORDER BY effective_at DESC, customer_version_id DESC
)
```

**Reason**

Do not destroy useful event/version history just to make a current-state table.

---

## 4. Customer Dimension Design

`warehouse.dim_customer` uses a hybrid SCD strategy.

### SCD Type 2 attributes

These create new historical periods:

- city
- state
- country
- postal_code
- customer_status

### Type 1 attributes

These overwrite across all historical rows:

- first_name
- last_name
- email
- phone
- date_of_birth
- signup_date

### Why hybrid?

Location/status are useful historically.

Email, phone, names, etc. are treated as latest/current corrections or contact information.

---

## 5. SCD2 Validity Convention

Validity interval:

```text
[valid_from, valid_to)
```

Meaning:

- `valid_from` is inclusive
- `valid_to` is exclusive
- current row uses `valid_to = NULL`

Example:

```text
Pune
09:00 <= t < 15:00

Hyderabad
15:00 <= t
```

No artificial subtraction of one second.

---

## 6. Important SQL Patterns Learned

### `IS DISTINCT FROM`

Used instead of `<>` for change detection because it handles `NULL` safely.

```text
NULL vs NULL   -> not distinct
NULL vs value  -> distinct
value vs value -> normal comparison
```

---

### `LAG()`

Used to find the state immediately before an incoming version.

For the first row in a batch, predecessor comes from the current warehouse row.

For later rows, predecessor comes from the previous staging row.

Example:

```text
warehouse current = Mumbai

batch:
Pune
Hyderabad
```

Correct comparisons:

```text
Mumbai -> Pune
Pune   -> Hyderabad
```

---

### `LEAD()`

Used to derive the next historical boundary.

Example:

```text
Pune       valid_from 09:00
Hyderabad  valid_from 15:00
```

Then:

```text
Pune       valid_to = 15:00
Hyderabad  valid_to = NULL
```

---

### Running `SUM()`

Used during the initial full SCD2 load to build SCD groups.

Pattern:

```sql
SUM(starts_new_scd2_version) OVER (
    PARTITION BY customer_id
    ORDER BY effective_at, customer_version_id
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
)
```

This is a gaps-and-islands style technique.

---

## 7. Initial Full Warehouse Load

The initial loader rebuilds `warehouse.dim_customer`.

It:

1. compares staging versions using `LAG()`
2. detects SCD2 boundaries
3. creates SCD groups
4. derives validity periods with `LEAD()`
5. selects latest Type 1 values per customer
6. inserts warehouse history

This is intentionally different from incremental ETL.

---

## 8. Incremental ETL V1

### Goal

Process only staging rows newer than the previous successful run.

Control table:

```text
control.pipeline_watermark
```

Key field:

```text
last_processed_version_id
```

The watermark is a processing position, not a row count.

Identity gaps are acceptable.

---

### V1 assumption

Only one unprocessed version per customer per ETL run.

Safety guard:

```sql
CREATE UNIQUE INDEX tmp_one_change_per_customer
ON tmp_customer_changes(customer_id);
```

### Why this guard existed

V1 could not safely process:

```text
Mumbai -> Pune -> Hyderabad
```

in one batch.

Without the guard, multiple versions could be compared against the same warehouse current row and generate incorrect history.

So V1 intentionally failed instead of guessing.

---

## 9. Failure We Reproduced: Multiple Versions Per Customer

### Issue

Two new versions arrived before ETL:

```text
42 | customer 101 | Pune
43 | customer 101 | Hyderabad
```

### Reason

V1 only supported one row per customer/run.

### Failure

The temporary unique index failed:

```text
Key (customer_id)=(101) is duplicated.
```

PostgreSQL marked the transaction aborted and the script rolled back.

### Proof that V1 failed safely

After the failure:

```text
warehouse current = Mumbai
watermark          = 33
versions 42,43     = still unprocessed
```

### Lesson

Fail-safe ETL is better than silently corrupting dimensional history.

---

## 10. Incremental ETL V2 — Set-Based Design

We rejected a row-by-row PL/pgSQL loop.

### Why

The previous state of each incoming version can be derived set-wise:

- first version -> warehouse current row
- later versions -> `LAG()` of previous batch row

The end of each SCD2 state can be derived using `LEAD()`.

Therefore no procedural loop is needed.

### V2 flow

```text
BEGIN
  |
  +-- lock watermark row
  |
  +-- tmp_batch
  |     all rows after watermark
  |     ROW_NUMBER() per customer
  |
  +-- guards
  |     late arrival
  |     same-time conflicting SCD2 state
  |
  +-- LAG()
  |     real predecessor
  |
  +-- tmp_scd2_changes
  |     only meaningful SCD2 changes
  |
  +-- LEAD()
  |     valid_to
  |
  +-- close existing current row once
  |
  +-- insert complete SCD2 chain in one statement
  |
  +-- latest row from tmp_batch
  |     Type 1 update independently
  |
  +-- advance watermark monotonically
  |
COMMIT
```

---

## 11. Why Type 1 Must Be Independent of SCD2 Changes

Important example:

```text
Mumbai | old@email
Mumbai | new@email
```

There is:

```text
0 SCD2 change
1 Type1 change
```

Therefore Type 1 updates must read from:

```text
tmp_batch
```

not:

```text
tmp_scd2_changes
```

Otherwise a pure email-change batch would silently do nothing.

---

## 12. No-Op SCD2 Versions

Example:

```text
09:00 Delhi | priya@gmail.com
12:00 Delhi | priya.work@gmail.com
15:00 Jaipur | priya.work@gmail.com
```

SCD2 interpretation:

```text
Pune   -> Delhi   = real SCD2 change
Delhi  -> Delhi   = no SCD2 change
Delhi  -> Jaipur  = real SCD2 change
```

Warehouse result:

```text
Pune
Delhi
Jaipur
```

There is no useless second Delhi history row.

The 12:00 row still matters for Type 1 processing.

---

## 13. V2 End-to-End Test That Passed

Customer 200 started as:

```text
Priya | Pune | priya@gmail.com
```

Incoming batch:

```text
54 | Delhi  | priya@gmail.com      | 09:00
55 | Delhi  | priya.work@gmail.com | 12:00
56 | Jaipur | priya.work@gmail.com | 15:00
```

Final warehouse:

```text
Pune    -> 31 Aug 09:00
Delhi   -> 31 Aug 15:00
Jaipur  -> current
```

All three historical rows contain:

```text
priya.work@gmail.com
```

Watermark advanced:

```text
43 -> 56
```

This proved:

- multiple versions/customer/run
- SCD2 sequencing
- SCD2 no-op collapsing
- Type1-only change inside a mixed batch
- correct `LAG()`
- correct `LEAD()`
- independent Type1 path
- monotonic watermark

---

## 14. Empty-Batch Test

V2 was executed with no rows after the watermark.

Result:

```text
tmp_batch        = 0
warehouse update = 0
warehouse insert = 0
Type1 update     = 0
watermark update = 0
COMMIT            succeeded
```

Watermark stayed unchanged.

### Lesson

An incremental ETL should be safe to rerun when there is no work.

---

## 15. Transaction Design

Warehouse changes and watermark movement belong in the same transaction.

Correct pattern:

```text
BEGIN
    warehouse changes
    Type1 updates
    control/watermark update
COMMIT
```

If anything fails:

```text
ROLLBACK
```

The watermark must not claim data was processed if warehouse changes failed.

---

## 16. Watermark Decisions

Watermark field:

```text
customer_version_id
```

Why:

- monotonically generated identity
- easy incremental filtering
- gaps are harmless
- no dependence on source timestamp quality

Advance rule:

```sql
new_max IS NOT NULL
AND new_max > current_watermark
```

This prevents:

- NULL watermark on empty batch
- moving watermark backwards

---

## 17. Watermark Lock

V2 locks the pipeline control row:

```sql
SELECT last_processed_version_id
FROM control.pipeline_watermark
WHERE pipeline_name = 'dim_customer_incremental'
FOR UPDATE;
```

### Reason

Avoid concurrent ETL runs reading the same watermark and processing the same batch simultaneously.

---

## 18. Permanent Warehouse Integrity Rules

### Positive validity period

Already enforced:

```sql
CHECK (
    valid_to IS NULL
    OR valid_to > valid_from
)
```

Prevents zero-duration and inverted history rows.

---

### One current row per customer

Partial unique index:

```sql
CREATE UNIQUE INDEX ux_dim_customer_one_current
ON warehouse.dim_customer (customer_id)
WHERE is_current = TRUE;
```

---

### No overlapping customer history

Using `btree_gist` and an exclusion constraint:

```sql
EXCLUDE USING gist (
    customer_id WITH =,
    tstzrange(valid_from, valid_to, '[)') WITH &&
)
```

This makes PostgreSQL reject overlapping SCD periods even if ETL logic has a bug.

---

## 19. V2 Safety Guards

### Late-arriving snapshot

V2 currently supports append-only history.

If an incoming `effective_at` is older than or equal to the current warehouse row's `valid_from`, V2 rejects the batch.

Why:

A historical correction belongs inside existing history and requires interval rewriting.

That will be handled in a future version.

---

### Same-time conflicting SCD2 states

Example:

```text
101 | Pune      | 09:00
101 | Hyderabad | 09:00
```

Even though `customer_version_id` gives deterministic ingestion order, business-time order is ambiguous.

V2 rejects conflicting SCD2 states at the same `effective_at`.

---

### Invalid period

Derived SCD2 periods must satisfy:

```text
valid_to > valid_from
```

A temporary guard catches problems before warehouse writes, while the permanent table constraint remains the final protection.

---

## 20. Important Data Contract

Current staging versions are treated as **full customer snapshots**.

Example:

```text
version 1:
Ali | Mumbai | old@email

version 2:
Ali | Mumbai | new@email
```

Not sparse CDC:

```text
version 2:
email = new@email
city  = NULL because unchanged
```

If sources later provide partial updates, staging must first carry forward unchanged values before SCD comparison.

---

## 21. Identity Sequence Gaps

Observed:

```text
customer_version_id 18
then 25
then 33
then 42...
```

This is normal.

PostgreSQL sequences can allocate values before an insert later conflicts or rolls back.

Therefore:

- identity IDs guarantee uniqueness/order
- they do not guarantee gapless numbering
- `MAX(id)` watermark still works

---

## 22. Current Customer Pipeline Status

Implemented:

- permissive RAW customer ingestion
- quality audit table
- quality detection rules
- cleaned staging history
- current-state staging view
- initial hybrid SCD1/SCD2 dimension load
- incremental watermark
- V1 incremental loader
- V1 fail-safe test
- V2 set-based multi-version loader
- empty-batch safety
- late-arrival guard
- same-time ambiguity guard
- monotonic watermark
- warehouse integrity constraints

Current V2 watermark after latest test:

```text
56
```

---

## 23. Next Work

Suggested next sequence:

1. deliberately test late-arriving version guard
2. deliberately test same-time conflicting SCD2 guard
3. deliberately test warehouse overlap constraint
4. add ETL run audit table
5. consider V3 late-arriving-history repair
6. then move to other entities such as products/orders

---

## 24. Rule for Updating This File

Whenever we hit something non-obvious, add:

```text
Issue
Reason
Risk
Decision
Solution
How we tested it
What we learned
```

This file should explain not only **what the final SQL is**, but **why the architecture ended up that way**.
