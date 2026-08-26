# RetailPulse SQL Warehouse — INTERVIEW NOTES

> Purpose: convert the project into interview-ready explanations.
>
> Focus on architecture decisions, trade-offs, failures, SQL patterns, and reliability — not just "I wrote some queries."

---

## 1. 30-Second Project Explanation

**RetailPulse SQL Warehouse** is a PostgreSQL-only Data Engineering project where I built a layered warehouse pipeline using RAW, staging, warehouse, audit, and control schemas.

I implemented data-quality handling, typed staging, a hybrid SCD Type 1 / Type 2 customer dimension, initial historical loading, and a set-based incremental ETL pipeline using window functions such as `ROW_NUMBER()`, `LAG()`, and `LEAD()`.

The incremental pipeline supports multiple versions for the same customer in one batch, collapses SCD2 no-op changes, handles Type 1 attributes independently, uses transactional watermarks, and has database-level constraints to prevent overlapping history or multiple current rows.

---

## 2. 2-Minute Architecture Walkthrough

```text
raw.customers
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

control.pipeline_watermark
    |
    +--> incremental processing state
```

### RAW

RAW is intentionally permissive.

Most source attributes are stored as text so malformed source data can land and be audited instead of being lost before ingestion.

### Audit

Data-quality issues are stored separately with:

- severity
- action
- issue code
- original value
- raw record lineage

### Staging

Staging converts usable records into typed values and preserves every usable customer version.

### Warehouse

The customer dimension uses hybrid SCD:

- location/status = Type 2
- contact/name fields = Type 1

### Control

A watermark records the highest successfully processed staging version.

---

## 3. Why Did You Make RAW Fields TEXT?

**Answer**

I wanted RAW to preserve source truth instead of enforcing warehouse-quality assumptions at ingestion time.

For example, `customer_id`, timestamps, email, and dates can arrive malformed. If RAW casts them immediately, bad rows can fail before I can audit them.

So RAW is permissive, while pipeline metadata like `source_system`, `batch_id`, and `ingested_at` is strict.

The staging layer is where I validate and cast.

---

## 4. Why Isn't `customer_id` the RAW Primary Key?

Because RAW stores source versions/events, not a single canonical customer row.

A customer can legitimately appear multiple times:

```text
101 | Bangalore
101 | Chandigarh
101 | Delhi
```

The RAW primary key is a technical identity:

```text
raw_record_id
```

`customer_id` remains the business key.

---

## 5. How Did You Handle Bad Data?

I used the rule:

```text
Identity problem -> reject record
Attribute problem -> preserve record and handle attribute
```

Examples:

```text
missing customer_id -> REJECT
invalid customer_id -> REJECT
bad email           -> NULLIFY + warning
missing city        -> flag
bad updated_at      -> fallback
```

Rejected records remain in RAW for traceability; they are simply not promoted to trusted staging.

---

## 6. Why Have Both Staging History and a Current View?

The physical staging history table preserves every usable version.

The current-state view uses:

```sql
ROW_NUMBER() OVER (
    PARTITION BY customer_id
    ORDER BY effective_at DESC, customer_version_id DESC
)
```

and filters rank 1.

That gives current state without destroying historical source versions.

---

## 7. Explain Your SCD Strategy

I use a hybrid approach.

### Type 2

- city
- state
- country
- postal_code
- customer_status

These create historical rows.

### Type 1

- first_name
- last_name
- email
- phone
- date_of_birth
- signup_date

These are updated across all historical rows.

Reason: location/status matter for historical analysis, while contact/name fields are treated as latest-value attributes.

---

## 8. Why Use `IS DISTINCT FROM` Instead of `<>`?

Because normal equality comparisons with `NULL` produce `UNKNOWN`.

For SCD change detection I need:

```text
NULL vs NULL  -> unchanged
NULL vs value -> changed
```

`IS DISTINCT FROM` gives exactly that behavior.

---

## 9. Explain `LAG()` in Your Incremental Loader

The challenge is multiple versions for the same customer in one batch.

Example:

```text
warehouse current = Mumbai

incoming:
09:00 Pune
15:00 Hyderabad
```

Incorrect comparison:

```text
Mumbai -> Pune
Mumbai -> Hyderabad
```

Correct comparison:

```text
Mumbai -> Pune
Pune   -> Hyderabad
```

I use `LAG()` for all versions after the first.

The first incoming version compares against the current warehouse row.

---

## 10. Explain `LEAD()` in Your Incremental Loader

Once real SCD2 changes are identified, each row's `valid_to` is the next SCD2 change's `effective_at`.

Example:

```text
Pune       starts 09:00
Hyderabad  starts 15:00
```

Then:

```text
Pune       09:00 -> 15:00
Hyderabad  15:00 -> NULL
```

`LEAD(effective_at)` derives this set-wise.

---

## 11. Why Did You Avoid a PL/pgSQL Loop?

Initially a row-by-row loop looked natural because each change seems to depend on the result of the previous one.

But the input batch already contains the ordered state sequence.

For each row:

- predecessor = warehouse current for first row
- predecessor = `LAG()` for later rows
- end boundary = `LEAD()`

So the entire SCD2 chain can be derived set-wise.

That is simpler, more SQL-centric, and typically more scalable than procedural row-by-row processing.

---

## 12. What Was the Biggest ETL Failure You Found?

V1 only supported one incoming version per customer per run.

I deliberately tested:

```text
customer 101
Pune
Hyderabad
```

before one ETL execution.

V1 had a temporary unique index on `customer_id`, so PostgreSQL failed with a duplicate key error.

The transaction rolled back.

I verified:

```text
warehouse current remained Mumbai
watermark remained unchanged
both staging rows remained unprocessed
```

That proved V1 failed safely instead of corrupting history.

---

## 13. How Did V2 Fix That?

V2 is set-based.

It:

1. captures all rows after the watermark
2. orders them per customer
3. uses `LAG()` to identify the real predecessor
4. removes SCD2 no-op versions
5. uses `LEAD()` for validity periods
6. closes the previous warehouse current row once
7. inserts the whole SCD2 chain in one statement
8. applies latest Type 1 values separately
9. advances the watermark
10. commits everything atomically

---

## 14. Why Must Type 1 Processing Be Separate?

A batch can contain no SCD2 change at all:

```text
Mumbai | old@email
Mumbai | new@email
```

If Type 1 processing read only from the SCD2-change table, the email change would disappear because that table has zero rows.

So Type 1 values are taken from the latest row in the full incoming batch, not from the SCD2 subset.

---

## 15. What Is an SCD2 No-Op?

Example:

```text
09:00 Delhi
12:00 Delhi
15:00 Jaipur
```

The second Delhi snapshot does not create a new SCD2 historical row.

The SCD2 chain becomes:

```text
Delhi 09:00 -> 15:00
Jaipur 15:00 -> current
```

But the 12:00 row may still matter for Type 1 fields.

---

## 16. How Do You Make the Incremental ETL Idempotent?

Main mechanisms:

- watermark filters already processed staging versions
- empty batch performs no warehouse or watermark changes
- quality issue inserts use `ON CONFLICT DO NOTHING`
- RAW/staging lineage keys prevent duplicate promotion
- transaction keeps warehouse state and watermark synchronized

An empty V2 run was explicitly tested and committed successfully with zero changes.

---

## 17. Why Use a Watermark?

Without a watermark, every incremental run would need to scan/reprocess all historical staging data.

The watermark records:

```text
highest customer_version_id successfully processed
```

New batch condition:

```sql
customer_version_id > last_processed_version_id
```

The watermark is advanced only after warehouse work succeeds.

---

## 18. Why Use `customer_version_id` Instead of Timestamp as Watermark?

Source timestamps can be malformed, duplicated, late, or corrected.

The staging identity version is controlled by the database and gives a deterministic processing position.

Sequence gaps do not matter.

Example:

```text
18 -> 25 -> 33 -> 42
```

A watermark is a position, not a row count.

---

## 19. How Do You Prevent Watermark Corruption?

Three protections:

1. update only when batch MAX is not NULL
2. update only when new MAX > current watermark
3. update inside the same transaction as warehouse changes

So an empty batch cannot set the watermark to NULL, and replay/mis-ordering cannot move it backwards.

---

## 20. Why Lock the Watermark Row?

V2 does:

```sql
... FOR UPDATE
```

on the pipeline watermark row.

Reason:

If two ETL instances start at the same time, both could otherwise read the same watermark and try to process the same batch.

The row lock serializes that pipeline's incremental processing.

---

## 21. What Warehouse Integrity Constraints Did You Add?

### Validity check

```text
valid_to is NULL
or
valid_to > valid_from
```

Prevents zero-duration and inverted periods.

### Partial unique index

Only one `is_current = TRUE` row per customer.

### GiST exclusion constraint

No overlapping validity ranges for the same customer.

This means the database protects dimensional history even if loader logic has a defect.

---

## 22. Why Use an Exclusion Constraint?

A unique key does not prevent this:

```text
Delhi 25 Aug -> 30 Aug
Mumbai 27 Aug -> current
```

Those are different rows but their validity ranges overlap.

PostgreSQL range types + GiST allow the database to reject overlapping periods structurally.

---

## 23. What Does `[)` Mean?

The warehouse uses half-open intervals:

```text
[valid_from, valid_to)
```

Example:

```text
Pune       09:00 -> 15:00
Hyderabad  15:00 -> NULL
```

At exactly 15:00, Hyderabad is valid and Pune is not.

This avoids subtracting arbitrary seconds or milliseconds.

---

## 24. How Do You Handle Late-Arriving Data?

V2 does **not** rewrite historical intervals yet.

If an incoming version's `effective_at` is earlier than or equal to the current warehouse row's `valid_from`, the batch is rejected.

Reason:

That event belongs inside already-built history, so safely processing it requires interval repair rather than normal append logic.

I intentionally fail closed and plan to handle it in a later V3.

---

## 25. Why Reject Same-Time Conflicting States?

Example:

```text
101 | Pune      | 09:00
101 | Hyderabad | 09:00
```

`customer_version_id` can tell me ingestion order, but it cannot prove business-time order.

Creating a zero-duration Pune state would be artificial.

So V2 rejects conflicting SCD2 states at the same effective timestamp.

---

## 26. What Is the Current Staging Data Contract?

Each staging version is a complete cleaned customer snapshot.

It is **not** sparse CDC.

If a source later emits partial updates such as:

```text
email = new@email
city = NULL because unchanged
```

then carry-forward logic must reconstruct the full state before SCD comparison.

---

## 27. Strong Interview Story: V1 -> V2

Use this answer:

> My first incremental SCD2 loader intentionally supported only one version per customer per run. I protected it with a temporary unique index so unsupported batches failed instead of creating incorrect history. I then reproduced that failure with two customer updates in one batch and verified the transaction rolled back with the warehouse and watermark unchanged.
>
> To remove the limitation, I redesigned the loader set-wise. I ordered versions per business key with `ROW_NUMBER()`, used the current dimension row as the first baseline, `LAG()` for subsequent predecessors, filtered only real Type 2 changes with `IS DISTINCT FROM`, and used `LEAD()` to derive validity windows. Type 1 fields were updated independently from the latest full batch snapshot. The watermark is locked and advanced monotonically in the same transaction.
>
> I also added database-level constraints for one current row, positive validity ranges, and non-overlapping history.

---

## 28. Example End-to-End Test

Customer 200:

Initial:

```text
Pune | priya@gmail.com
```

Batch:

```text
09:00 Delhi  | priya@gmail.com
12:00 Delhi  | priya.work@gmail.com
15:00 Jaipur | priya.work@gmail.com
```

Result:

```text
Pune    -> 09:00
Delhi   09:00 -> 15:00
Jaipur  15:00 -> current
```

All historical rows show:

```text
priya.work@gmail.com
```

This single test proves:

- multiple rows/customer/batch
- Type 2 state change
- Type 2 no-op collapse
- Type 1 update
- correct validity periods
- successful watermark advancement

---

## 29. Trade-Off: `valid_to = NULL`

I kept `NULL` for the current row because that convention was already established in the model and is easy to understand.

Trade-off:

As-of queries must use something like:

```sql
valid_from <= :timestamp
AND (
    valid_to > :timestamp
    OR valid_to IS NULL
)
```

or `COALESCE(valid_to, 'infinity')`.

Consistency was more valuable than changing conventions mid-project.

---

## 30. Questions I Should Be Ready For

Be able to answer:

- Why RAW is permissive
- Why business key is not RAW PK
- Why audit issues are separate
- How staging chooses effective timestamps
- Type 1 vs Type 2 decision
- Why `IS DISTINCT FROM`
- `ROW_NUMBER()` vs `RANK()`
- `LAG()` vs self join
- `LEAD()` for SCD ranges
- why no PL/pgSQL loop
- watermark design
- transaction boundaries
- concurrent ETL protection
- late-arriving data
- no-op updates
- full snapshots vs sparse CDC
- overlap protection
- idempotency
- sequence gaps
- how V1 failed and why that was useful
- what V3 would improve

---

## 31. What I Would Build Next

Strong answer:

> I would next add an ETL run-audit table containing run ID, start/end time, input count, inserted/updated counts, watermark before/after, and status. After that I would implement late-arriving SCD2 repair, because V2 currently intentionally rejects historical corrections rather than rewriting existing validity intervals.

---

## 32. Interview Rule

Do not describe the project as:

> "I made a customer table and used window functions."

Describe it as:

> "I designed an incremental dimensional-history pipeline, reproduced its failure modes, and added both ETL-level and database-level protections."

That is the engineering story.
