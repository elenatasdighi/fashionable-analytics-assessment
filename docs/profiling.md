# Raw data profiling — `raw.fashionable_sales_raw`

_Generated 2026-08-04 17:08 by `scripts/profile_raw.py` (read-only DuckDB connection)._

Presentation-shaped: seven slide sections mirror 1:1 with the content slides of `presentations/data_profiling.pptx`. An **Appendix — Detailed evidence** at the bottom carries the raw counts each slide summarises and the traceability behind design decisions D1–D8.

<!-- ===== SLIDE 1 — DATA EXPLORATION ===== -->
## Slide 1 — Data Exploration

### Dataset overview

| Metric | Finding |
| --- | --- |
| Records | 128,975 |
| Unique orders | 120,378 |
| Source columns | 24 |
| Date range | 31 Mar 2022 – 29 Jun 2022 (91 distinct days) |
| SKUs | 7,195 |
| Styles | 1,377 |
| Categories | 9 |
| Sizes | 11 |
| Ship cities | 8,955 |

**Business concepts identified:** Orders · Products · Sales · Location · Fulfilment

**Goal:** understand the business process and source grain before modelling.

<!-- SLIDE 1 END -->

<!-- ===== SLIDE 2 — UNDERSTANDING THE SOURCE GRAIN ===== -->
## Slide 2 — Understanding the Source Grain

### One order ≠ one row

| Metric | Finding |
| --- | --- |
| Records | 128,975 |
| Unique orders | 120,378 |
| Extra order lines | 8,597 |
| Orders with multiple rows | 6,846 |
| Max rows for one order | 12 |
| Exact-duplicate (Order ID, SKU) groups | 7 |
| Extra rows inside those groups | 7 |

**Finding:** source grain is **order × SKU line item**. `(Order ID, SKU)` is *almost* unique — the 7 exact-duplicate groups mean staging needs an explicit dedupe step.

### Product hierarchy

`Style → SKU / Product Variant → Size`

| Metric | Finding |
| --- | --- |
| SKUs | 7,195 |
| Styles | 1,377 |
| Sizes | 11 |
| Styles with multiple SKUs | 1,180 |
| Max SKUs for one style | 14 |

**Why it matters:** the model must support drill-down at both **Style/Category** and **SKU/Size**. Findings drove the fact grain, not the reverse.

<!-- SLIDE 2 END -->

<!-- ===== SLIDE 3 — DATA QUALITY — COMPLETENESS & UNIQUENESS ===== -->
## Slide 3 — Data Quality — Completeness & Uniqueness

**Checks performed:** Completeness · Uniqueness · Validity · Consistency · Business Rules

| Finding | Result |
| --- | --- |
| Business-level exact duplicate rows* | 6 |
| Missing Amount | 7,795 |
| Qty = 0 | 12,807 |
| Negative Qty | 0 |
| Negative Amount | 0 |
| Invalid dates (format %m-%d-%y) | 0 |
| Missing shipping info | 33 |
| SKU → Style inconsistencies | 0 |
| SKU → Category inconsistencies | 0 |
| SKU → Size inconsistencies | 0 |
| Status ↔ Courier Status contradictions | 218 |

\*Exact duplicates ignore the technical `index` field.

> `(Order ID, SKU)` cannot be assumed unique until dedupe. `SKU` **is** consistent with Style / Category / Size — master data is clean.

<!-- SLIDE 3 END -->

<!-- ===== SLIDE 4 — DATA QUALITY — CROSS-FIELD & GEOGRAPHY ===== -->
## Slide 4 — Data Quality — Cross-field & Geography

### `Amount` ↔ `currency` null pattern

- both NULL `7,795` · only Amount NULL `0` · only currency NULL `0` → **perfectly correlated** — `currency` carries no independent info.

### `Fulfilment` ↔ `fulfilled-by`

| Fulfilment | fulfilled-by | count |
| --- | --- | --- |
| Fashionable | <NULL> | 89698 |
| Merchant | Easy Ship | 39277 |

→ **perfectly redundant** — drop `fulfilled-by` in staging.

### Status ↔ Courier Status contradictions (218 rows, 0.17%)

| Status | Courier Status | count |
| --- | --- | --- |
| Shipped | Unshipped | 115 |
| Shipped | Cancelled | 93 |
| Pending | Shipped | 10 |

→ real but noise-level — flag with warn-level dbt test, don't reject.

### Geography casing collapse

- `ship-city`: **8,955** raw → **7,297** after `UPPER(TRIM())` — **19%** duplication from casing.
- `ship-state`: **69** raw → **47** normalized (32% duplication). India has 36 states+UTs; normalized 47 → residual misspellings.
- `ship-country`: **1** — a constant.

<!-- SLIDE 4 END -->

<!-- ===== SLIDE 5 — NOT EVERY ANOMALY IS BAD DATA ===== -->
## Slide 5 — Not Every Anomaly Is Bad Data

### Business context of anomalies

| Condition | Total | Cancelled | Shipped |
| --- | --- | --- | --- |
| Qty = 0 | 12,807 | 12,701 | 104 |
| Amount is missing | 7,795 | 7,566 | 219 |

- **Cancelled orders with `Amount > 0`:** **10,766** — list price captured at cancel. Naïvely summing raw `Amount` inflates revenue ~15%.
- **Active-order anomalies to flag** (not delete):
  - Shipped + Qty = 0: **104**
  - Shipped + Amount missing: **219**

### Multi-value complexity

- **`promotion-ids`** — 79,822 rows carry data (62%). Longest value: 2,497 chars, up to **36** promo IDs per row (avg ~9.0).
- Textbook Kimball answer is a `bridge_order_promotion` M:N + `dim_promotion`, but promo IDs are opaque strings with no metadata → `dim_promotion` would be degenerate. MVP surfaces `promo_count` on the fact; bridge deferred.

**Key insight:** NULL / unusual values don't automatically mean bad data. The business generates NULL-carrying rows deliberately (cancellations). Silent filtering destroys signal.

<!-- SLIDE 5 END -->

<!-- ===== SLIDE 6 — DATA QUALITY TREATMENT STRATEGY ===== -->
## Slide 6 — Data Quality Treatment Strategy

### Actions

| Action | Examples |
| --- | --- |
| CLEAN | Types, snake_case names, whitespace/casing, city/state normalization, date parsing |
| KEEP | Cancelled orders, valid business NULLs, `_raw` audit columns |
| FLAG | Shipped + Qty = 0 · Shipped + missing Amount · Status/Courier contradictions |
| EXCLUDE | Technical `index`, `Unnamed: 22` (79,925 rows are literal "False"), `fulfilled-by` (redundant), constants `currency` / `ship-country` |
| TEST | Line-item PK uniqueness · fact↔dim relationships · accepted values for Status · row-count reconciliation vs raw |

- Non-empty `Unnamed: 22` values: **79,925** (all literal "False") — pandas export artifact, safe to drop.

**Guiding principle:** *improve data quality without destroying business information*.

<!-- SLIDE 6 END -->

<!-- ===== SLIDE 7 — LOCKED DECISIONS D1–D8 ===== -->
## Slide 7 — Locked Decisions D1–D8

| Ref | Decision |
| --- | --- |
| D1 | Cancelled orders kept · `is_cancelled` flag + derived `revenue_amount` (= 0 if cancelled) |
| D2 | Fact grain = order × SKU line item · surrogate key from `(order_id, sku)` after dedupe |
| D3 | `promo_count` on fact · `bridge_order_promotion` + `dim_promotion` deferred |
| D4 | Drop `Unnamed: 22`, `fulfilled-by`, `currency`, `ship-country` in staging |
| D5 | `dim_order_status` with raw `status_detail` + 5-group `status_group` (Delivered / Shipped / Pending / Cancelled / Returned) |
| D6 | Let 218 contradictions pass · warn-level dbt test at 250 threshold |
| D7 | Canonical `UPPER(TRIM())` city/state · keep `_raw` audit columns |
| D8 | Cast `Date` → `DATE` with `strptime('%m-%d-%y')` in staging |

Full rationale + interview soundbites live in the pptx (slide 7 speaker notes).

> With grain, business semantics and data quality understood, next step is Architecture & Data Modelling.

<!-- SLIDE 7 END -->

## Appendix — Detailed evidence

Raw numbers backing the slides above. Every D1–D8 decision cites these.

### A1. Missing values per column (NULL or empty string)

| Column | Missing (NULL or empty) | % missing |
| --- | --- | --- |
| fulfilled-by | 89,698 | 69.55% |
| promotion-ids | 49,153 | 38.11% |
| Unnamed: 22 | 49,050 | 38.03% |
| currency | 7,795 | 6.04% |
| Amount | 7,795 | 6.04% |
| Courier Status | 6,872 | 5.33% |
| ship-city | 33 | 0.03% |
| ship-state | 33 | 0.03% |
| ship-postal-code | 33 | 0.03% |
| ship-country | 33 | 0.03% |
| index | 0 | 0.00% |
| Order ID | 0 | 0.00% |
| Date | 0 | 0.00% |
| Status | 0 | 0.00% |
| Fulfilment | 0 | 0.00% |
| Sales Channel | 0 | 0.00% |
| ship-service-level | 0 | 0.00% |
| Style | 0 | 0.00% |
| SKU | 0 | 0.00% |
| Category | 0 | 0.00% |
| Size | 0 | 0.00% |
| ASIN | 0 | 0.00% |
| Qty | 0 | 0.00% |
| B2B | 0 | 0.00% |

### A2. Categorical distributions

#### `Status` — 13 distinct values (top 15)

| value | count |
| --- | --- |
| Shipped | 77804 |
| Shipped - Delivered to Buyer | 28769 |
| Cancelled | 18332 |
| Shipped - Returned to Seller | 1953 |
| Shipped - Picked Up | 973 |
| Pending | 658 |
| Pending - Waiting for Pick Up | 281 |
| Shipped - Returning to Seller | 145 |
| Shipped - Out for Delivery | 35 |
| Shipped - Rejected by Buyer | 11 |
| Shipping | 8 |
| Shipped - Lost in Transit | 5 |
| Shipped - Damaged | 1 |

#### `Courier Status` — 3 distinct values (top 15)

| value | count |
| --- | --- |
| Shipped | 109487 |
| <NULL> | 6872 |
| Unshipped | 6681 |
| Cancelled | 5935 |

#### `Fulfilment` — 2 distinct values (top 15)

| value | count |
| --- | --- |
| Fashionable | 89698 |
| Merchant | 39277 |

#### `Sales Channel` — 2 distinct values (top 15)

| value | count |
| --- | --- |
| Fashionable.in | 128851 |
| Non-Fashionable | 124 |

#### `ship-service-level` — 2 distinct values (top 15)

| value | count |
| --- | --- |
| Expedited | 88615 |
| Standard | 40360 |

#### `Category` — 9 distinct values (top 15)

| value | count |
| --- | --- |
| Set | 50284 |
| kurta | 49877 |
| Western Dress | 15500 |
| Top | 10622 |
| Ethnic Dress | 1159 |
| Blouse | 926 |
| Bottom | 440 |
| Saree | 164 |
| Dupatta | 3 |

#### `Size` — 11 distinct values (top 15)

| value | count |
| --- | --- |
| M | 22711 |
| L | 22132 |
| XL | 20876 |
| XXL | 18096 |
| S | 17090 |
| 3XL | 14816 |
| XS | 11161 |
| 6XL | 738 |
| 5XL | 550 |
| 4XL | 427 |
| Free | 378 |

#### `currency` — 1 distinct values (top 15)

| value | count |
| --- | --- |
| INR | 121180 |
| <NULL> | 7795 |

#### `ship-country` — 1 distinct values (top 15)

| value | count |
| --- | --- |
| IN | 128942 |
| <NULL> | 33 |

#### `B2B` — 2 distinct values (top 15)

| value | count |
| --- | --- |
| False | 128104 |
| True | 871 |

#### `fulfilled-by` — 1 distinct values (top 15)

| value | count |
| --- | --- |
| <NULL> | 89698 |
| Easy Ship | 39277 |
