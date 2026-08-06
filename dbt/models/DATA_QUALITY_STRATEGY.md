{% docs __overview__ %}

# Fashionable Analytics — dbt project

Raw eCommerce sales CSV → Kimball star schema for sales and marketing analysis.

The **Data Quality Treatment Strategy** below is the contract every raw
column follows. It's the first thing to know about this project — deciding
what to CLEAN vs KEEP vs FLAG vs EXCLUDE vs TEST is 80% of the work.

---

## Data Quality Treatment Strategy

Each raw column is handled in one of five ways:

**CLEAN, KEEP, FLAG, EXCLUDE, or TEST**

The main rule is:

> Keep useful business information. Delete only when necessary.

### 1. CLEAN

Clean and standardize the data without changing its meaning.

Examples:

* Rename columns to `snake_case`
* Remove extra spaces
* Convert dates to `DATE`
* Convert quantity to `INTEGER`
* Convert amount to `DECIMAL`
* Standardize city and state names using `UPPER(TRIM())`
* Remove `.0` from postal codes
* Convert B2B values to `BOOLEAN`

Example:

```text
' mumbai ' → 'MUMBAI'
'05-29-22' → 2022-05-29
'400081.0' → '400081'
```

### 2. KEEP

Keep unusual data when it represents a real business situation.

Examples:

* Keep cancelled orders for cancellation analysis.
* Keep missing amounts because they mostly belong to cancelled orders.
* Keep missing courier status because some orders do not have a courier yet.
* Keep raw city and state values for auditing.
* Keep promotion IDs for possible future analysis.
* Keep `currency` and `ship_country` even though they are constants
  today (`INR` / `IN`). Accepted-values tests act as a canary — if the
  business expands internationally, the test fails at build time and
  we know to widen the downstream handling.

These rows are not deleted.

### 3. FLAG

Mark unusual records instead of removing them.

Examples:

* `is_cancelled` identifies cancelled orders.
* `revenue_amount` sets cancelled-order revenue to zero.
* Tests detect cancelled orders with non-zero revenue.
* Tests detect contradictions between order status and courier status.
* Tests monitor rows assigned to the `Unknown` region.

Small numbers may pass, medium numbers create warnings, and large numbers cause errors.

### 4. EXCLUDE

Remove only columns that have no useful business information.

Removed columns:

* `index`: pandas row number
* `Unnamed: 22`: export artefact
* `fulfilled-by`: duplicates information from `Fulfilment`

No rows are removed only because they contain `NULL`. Constants like
`currency` (`INR`) and `ship-country` (`IN`) are kept in staging + fact
under KEEP — see above.

### 5. TEST

Use automated dbt tests to ensure data quality.

Main tests check:

* Primary keys are unique and not null.
* Each `(order_id, sku)` combination is unique.
* Fact-table foreign keys match dimension-table keys.
* Status, season, and region contain only expected values.
* Staging row count matches the deduplicated raw data.
* Fact-table row count matches staging.
* Cancelled orders do not contain revenue.

There are 79 tests across 6 models.

## Main Rule

**Deleting data is the last option. Flagging problems is the first option.**

{% enddocs %}
