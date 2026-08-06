-- ============================================================================
-- profile_raw.sql — pure-SQL
-- ============================================================================
-- Every query below produces one of the numbers that appears in presentations which show the raw data profile.

-- ============================================================================
-- SLIDE 3 — Data exploration
-- Purpose: overview KPIs 
-- ============================================================================
SELECT
    COUNT(*)                                          AS records,
    COUNT(DISTINCT "Order ID")                        AS unique_orders,
    COUNT(DISTINCT "SKU")                             AS skus,
    COUNT(DISTINCT "Style")                           AS styles,
    COUNT(DISTINCT "Category")                        AS categories,
    COUNT(DISTINCT "Size")                            AS sizes,
    COUNT(DISTINCT "ship-city")                       AS ship_cities,
    MIN(TRY_STRPTIME("Date", '%m-%d-%y'))::DATE       AS date_min,
    MAX(TRY_STRPTIME("Date", '%m-%d-%y'))::DATE       AS date_max,
    COUNT(DISTINCT "Date")                            AS distinct_dates
FROM raw.fashionable_sales_raw;


-- ============================================================================
-- SLIDE 4 — Source grain: one row ≠ one order
-- ============================================================================

-- Q4.1 — How many orders span multiple rows, and what's the max line count?

SELECT
    COUNT(*) FILTER (WHERE line_count > 1)  AS orders_with_multiple_rows,
    MAX(line_count)                          AS max_rows_per_order
FROM (
    SELECT "Order ID", COUNT(*) AS line_count
    FROM raw.fashionable_sales_raw
    GROUP BY "Order ID"
);

-- Q4.2 — Product hierarchy: how deep is Style → SKU fan-out?
-- Feeds the "Styles with multiple SKUs" and "Max SKUs per style" KPIs.
SELECT
    COUNT(*) FILTER (WHERE sku_count > 1)  AS styles_with_multiple_skus,
    MAX(sku_count)                          AS max_skus_per_style
FROM (
    SELECT "Style", COUNT(DISTINCT "SKU") AS sku_count
    FROM raw.fashionable_sales_raw
    WHERE NOT ("Style" IS NULL OR TRIM("Style") = '')
    GROUP BY "Style"
);

-- Q4.3 — How many exact-duplicate (Order ID, SKU) pairs exist?
-- If > 0 the natural composite PK is not unique — staging needs DISTINCT.
SELECT
    COUNT(*)                            AS duplicate_groups,
    COALESCE(SUM(row_count - 1), 0)     AS extra_rows_in_dupe_groups
FROM (
    SELECT "Order ID", "SKU", COUNT(*) AS row_count
    FROM raw.fashionable_sales_raw
    GROUP BY "Order ID", "SKU"
    HAVING COUNT(*) > 1
);


-- ============================================================================
-- SLIDE 5 — Data quality — completeness & uniqueness
-- ============================================================================

-- Q5.1 — Business-level exact duplicate rows (ignoring the technical 'index').
-- Groups on every business column; anything with count > 1 is a full row dupe.
SELECT COALESCE(SUM(row_count - 1), 0) AS business_level_exact_duplicates
FROM (
    SELECT
        "Order ID", "Date", "Status", "Fulfilment", "Sales Channel",
        "ship-service-level", "Style", "SKU", "Category", "Size", "ASIN",
        "Courier Status", "Qty", "currency", "Amount", "ship-city",
        "ship-state", "ship-postal-code", "ship-country", "promotion-ids",
        "B2B", "fulfilled-by", "Unnamed: 22",
        COUNT(*) AS row_count
    FROM raw.fashionable_sales_raw
    GROUP BY
        "Order ID", "Date", "Status", "Fulfilment", "Sales Channel",
        "ship-service-level", "Style", "SKU", "Category", "Size", "ASIN",
        "Courier Status", "Qty", "currency", "Amount", "ship-city",
        "ship-state", "ship-postal-code", "ship-country", "promotion-ids",
        "B2B", "fulfilled-by", "Unnamed: 22"
    HAVING COUNT(*) > 1
);

-- Q5.2 — Aggregate quality counters (missing, zeros, negatives, invalid dates,
-- missing shipping fields). One-row output, one column per check.
SELECT
    COUNT(*) FILTER (WHERE "Amount" IS NULL OR TRIM("Amount") = '')                                   AS missing_amount,
    COUNT(*) FILTER (WHERE TRY_CAST("Qty" AS INT) = 0)                                                AS qty_zero,
    COUNT(*) FILTER (WHERE TRY_CAST("Qty" AS INT) < 0)                                                AS qty_negative,
    COUNT(*) FILTER (WHERE TRY_CAST("Amount" AS DOUBLE) < 0)                                          AS amount_negative,
    COUNT(*) FILTER (
        WHERE NOT ("Date" IS NULL OR TRIM("Date") = '')
          AND TRY_STRPTIME("Date", '%m-%d-%y') IS NULL
    )                                                                                                 AS invalid_dates,
    COUNT(*) FILTER (
        WHERE ("ship-city"        IS NULL OR TRIM("ship-city")        = '')
           OR ("ship-state"       IS NULL OR TRIM("ship-state")       = '')
           OR ("ship-postal-code" IS NULL OR TRIM("ship-postal-code") = '')
           OR ("ship-country"     IS NULL OR TRIM("ship-country")     = '')
    )                                                                                                 AS missing_shipping_info
FROM raw.fashionable_sales_raw;

-- differnt from Q5.1, which checks for exact duplicates, Q5.2 checks for missing or invalid values in specific columns.
/*
select * from raw.fashionable_sales_raw --courier status
where "Order ID"  = '407-8364731-6449117'
and SKU  = 'JNE3769-KR-L'
*/

-- Q5.3 — SKU-level attribute drift: does the same SKU ever carry different
-- Style / Category / Size across rows? Any > 0 means master-data inconsistency.
SELECT
    COUNT(*) FILTER (WHERE style_count    > 1) AS sku_style_drift,
    COUNT(*) FILTER (WHERE category_count > 1) AS sku_category_drift,
    COUNT(*) FILTER (WHERE size_count     > 1) AS sku_size_drift
FROM (
    SELECT
        "SKU",
        COUNT(DISTINCT NULLIF(TRIM("Style"),    '')) AS style_count,
        COUNT(DISTINCT NULLIF(TRIM("Category"), '')) AS category_count,
        COUNT(DISTINCT NULLIF(TRIM("Size"),     '')) AS size_count
    FROM raw.fashionable_sales_raw
    WHERE NOT ("SKU" IS NULL OR TRIM("SKU") = '')
    GROUP BY "SKU"
);


-- ============================================================================
-- SLIDE 6 — Data quality — cross-field & geography
-- ============================================================================

-- Q6.1 — Are Amount NULL and currency NULL the same rows?
SELECT
    COUNT(*) FILTER (
        WHERE ("Amount"   IS NULL OR TRIM("Amount")   = '')
          AND ("currency" IS NULL OR TRIM("currency") = '')
    ) AS both_null,
    COUNT(*) FILTER (
        WHERE ("Amount"   IS NULL OR TRIM("Amount")   = '')
          AND NOT ("currency" IS NULL OR TRIM("currency") = '')
    ) AS only_amount_null,
    COUNT(*) FILTER (
        WHERE NOT ("Amount" IS NULL OR TRIM("Amount") = '')
          AND ("currency"   IS NULL OR TRIM("currency") = '')
    ) AS only_currency_null
FROM raw.fashionable_sales_raw;

-- Q6.2 — Cross-tab Fulfilment × fulfilled-by. If only two combos exist and
-- they map 1:1, fulfilled-by is redundant and should be dropped in staging.
SELECT
    "Fulfilment",
    COALESCE(NULLIF(TRIM("fulfilled-by"), ''), '<NULL>') AS fulfilled_by,
    COUNT(*)                                              AS row_count
FROM raw.fashionable_sales_raw
GROUP BY 1, 2
ORDER BY 1, 2;

-- Q6.3 — Rows where Status disagrees with Courier Status.
-- Small counts (~200) → flag with a warn-level test rather than drop.
SELECT
    "Status",
    COALESCE("Courier Status", '<NULL>') AS courier_status,
    COUNT(*)                              AS row_count
FROM raw.fashionable_sales_raw
WHERE ("Status" = 'Shipped'     AND "Courier Status" IN ('Unshipped', 'Cancelled'))
   OR ("Status" LIKE 'Pending%' AND "Courier Status" = 'Shipped')
GROUP BY 1, 2
ORDER BY 3 DESC;

-- Q6.4 — Geography casing collapse: how many distinct values disappear once
-- we normalize with UPPER(TRIM())? Delta = duplication caused by casing alone.
SELECT
    COUNT(DISTINCT "ship-city")                     AS city_raw,
    COUNT(DISTINCT UPPER(TRIM("ship-city")))        AS city_normalized,
    COUNT(DISTINCT "ship-state")                    AS state_raw,
    COUNT(DISTINCT UPPER(TRIM("ship-state")))       AS state_normalized,
    COUNT(DISTINCT "ship-country")                  AS distinct_countries
FROM raw.fashionable_sales_raw;


-- ============================================================================
-- SLIDE 7 — Not every anomaly is bad data
-- ============================================================================

-- Q7.1 — Split Qty=0 and missing-Amount counts by Status family.
-- Shows that most anomalies are Cancelled-order artefacts (not bad data).
SELECT
    COUNT(*) FILTER (WHERE TRY_CAST("Qty" AS INT) = 0)                                                   AS qty_zero_total,
    COUNT(*) FILTER (WHERE TRY_CAST("Qty" AS INT) = 0 AND TRIM("Status") = 'Cancelled')                  AS qty_zero_cancelled,
    COUNT(*) FILTER (WHERE TRY_CAST("Qty" AS INT) = 0 AND TRIM("Status") LIKE 'Shipped%')                AS qty_zero_shipped,
    COUNT(*) FILTER (WHERE "Amount" IS NULL OR TRIM("Amount") = '')                                      AS amount_missing_total,
    COUNT(*) FILTER (WHERE ("Amount" IS NULL OR TRIM("Amount") = '') AND TRIM("Status") = 'Cancelled')   AS amount_missing_cancelled,
    COUNT(*) FILTER (WHERE ("Amount" IS NULL OR TRIM("Amount") = '') AND TRIM("Status") LIKE 'Shipped%') AS amount_missing_shipped
FROM raw.fashionable_sales_raw;

-- Q7.2 — Cancelled orders carrying a non-zero Amount.
-- These are list-price snapshots; drives D1 (derived revenue_amount = 0 when cancelled).
SELECT COUNT(*) AS cancelled_orders_with_amount_gt_zero
FROM raw.fashionable_sales_raw
WHERE "Status" = 'Cancelled'
  AND TRY_CAST("Amount" AS DOUBLE) > 0;

-- Q7.3 — Shape of the multi-valued promotion-ids column.
-- Comma-count heuristic: `commas + 1` = promo IDs per row. / in future we can have dim for promotions
SELECT
    COUNT(*) FILTER (
        WHERE NOT ("promotion-ids" IS NULL OR TRIM("promotion-ids") = '')
    )                                                                                        AS rows_with_promo,
    MAX(LENGTH("promotion-ids"))                                                              AS max_raw_length,
    MAX(LENGTH("promotion-ids") - LENGTH(REPLACE("promotion-ids", ',', '')) + 1)              AS max_promo_count_per_row,
    AVG(
        CASE
            WHEN NOT ("promotion-ids" IS NULL OR TRIM("promotion-ids") = '')
            THEN LENGTH("promotion-ids") - LENGTH(REPLACE("promotion-ids", ',', '')) + 1
        END
    )                                                                                         AS avg_promo_count_when_present
FROM raw.fashionable_sales_raw;


-- ============================================================================
-- SLIDE 8 — Data quality treatment strategy
-- ============================================================================

-- Q8.1 — How many rows carry a non-empty value in Unnamed: 22?
-- We expect 79,925 (all literal "False") — confirms it's a pandas export artefact.
SELECT COUNT(*) AS unnamed_22_non_empty
FROM raw.fashionable_sales_raw
WHERE NOT ("Unnamed: 22" IS NULL OR TRIM("Unnamed: 22") = '');


-- ============================================================================
-- APPENDIX A1 — Missing values per column (NULL or empty string)
-- ============================================================================
WITH per_column AS (
    SELECT 'index'              AS column_name, COUNT(*) FILTER (WHERE "index"              IS NULL OR TRIM("index")              = '') AS missing FROM raw.fashionable_sales_raw
    UNION ALL SELECT 'Order ID',              COUNT(*) FILTER (WHERE "Order ID"           IS NULL OR TRIM("Order ID")           = '') FROM raw.fashionable_sales_raw
    UNION ALL SELECT 'Date',                  COUNT(*) FILTER (WHERE "Date"               IS NULL OR TRIM("Date")               = '') FROM raw.fashionable_sales_raw
    UNION ALL SELECT 'Status',                COUNT(*) FILTER (WHERE "Status"             IS NULL OR TRIM("Status")             = '') FROM raw.fashionable_sales_raw
    UNION ALL SELECT 'Fulfilment',            COUNT(*) FILTER (WHERE "Fulfilment"         IS NULL OR TRIM("Fulfilment")         = '') FROM raw.fashionable_sales_raw
    UNION ALL SELECT 'Sales Channel',         COUNT(*) FILTER (WHERE "Sales Channel"      IS NULL OR TRIM("Sales Channel")      = '') FROM raw.fashionable_sales_raw
    UNION ALL SELECT 'ship-service-level',    COUNT(*) FILTER (WHERE "ship-service-level" IS NULL OR TRIM("ship-service-level") = '') FROM raw.fashionable_sales_raw
    UNION ALL SELECT 'Style',                 COUNT(*) FILTER (WHERE "Style"              IS NULL OR TRIM("Style")              = '') FROM raw.fashionable_sales_raw
    UNION ALL SELECT 'SKU',                   COUNT(*) FILTER (WHERE "SKU"                IS NULL OR TRIM("SKU")                = '') FROM raw.fashionable_sales_raw
    UNION ALL SELECT 'Category',              COUNT(*) FILTER (WHERE "Category"           IS NULL OR TRIM("Category")           = '') FROM raw.fashionable_sales_raw
    UNION ALL SELECT 'Size',                  COUNT(*) FILTER (WHERE "Size"               IS NULL OR TRIM("Size")               = '') FROM raw.fashionable_sales_raw
    UNION ALL SELECT 'ASIN',                  COUNT(*) FILTER (WHERE "ASIN"               IS NULL OR TRIM("ASIN")               = '') FROM raw.fashionable_sales_raw
    UNION ALL SELECT 'Courier Status',        COUNT(*) FILTER (WHERE "Courier Status"     IS NULL OR TRIM("Courier Status")     = '') FROM raw.fashionable_sales_raw
    UNION ALL SELECT 'Qty',                   COUNT(*) FILTER (WHERE "Qty"                IS NULL OR TRIM("Qty")                = '') FROM raw.fashionable_sales_raw
    UNION ALL SELECT 'currency',              COUNT(*) FILTER (WHERE "currency"           IS NULL OR TRIM("currency")           = '') FROM raw.fashionable_sales_raw
    UNION ALL SELECT 'Amount',                COUNT(*) FILTER (WHERE "Amount"             IS NULL OR TRIM("Amount")             = '') FROM raw.fashionable_sales_raw
    UNION ALL SELECT 'ship-city',             COUNT(*) FILTER (WHERE "ship-city"          IS NULL OR TRIM("ship-city")          = '') FROM raw.fashionable_sales_raw
    UNION ALL SELECT 'ship-state',            COUNT(*) FILTER (WHERE "ship-state"         IS NULL OR TRIM("ship-state")         = '') FROM raw.fashionable_sales_raw
    UNION ALL SELECT 'ship-postal-code',      COUNT(*) FILTER (WHERE "ship-postal-code"   IS NULL OR TRIM("ship-postal-code")   = '') FROM raw.fashionable_sales_raw
    UNION ALL SELECT 'ship-country',          COUNT(*) FILTER (WHERE "ship-country"       IS NULL OR TRIM("ship-country")       = '') FROM raw.fashionable_sales_raw
    UNION ALL SELECT 'promotion-ids',         COUNT(*) FILTER (WHERE "promotion-ids"      IS NULL OR TRIM("promotion-ids")      = '') FROM raw.fashionable_sales_raw
    UNION ALL SELECT 'B2B',                   COUNT(*) FILTER (WHERE "B2B"                IS NULL OR TRIM("B2B")                = '') FROM raw.fashionable_sales_raw
    UNION ALL SELECT 'fulfilled-by',          COUNT(*) FILTER (WHERE "fulfilled-by"       IS NULL OR TRIM("fulfilled-by")       = '') FROM raw.fashionable_sales_raw
    UNION ALL SELECT 'Unnamed: 22',           COUNT(*) FILTER (WHERE "Unnamed: 22"        IS NULL OR TRIM("Unnamed: 22")        = '') FROM raw.fashionable_sales_raw
),
total AS (SELECT COUNT(*) AS n FROM raw.fashionable_sales_raw)
SELECT
    p.column_name,
    p.missing,
    ROUND(100.0 * p.missing / t.n, 2) AS pct_missing
FROM per_column p CROSS JOIN total t
ORDER BY p.missing DESC;


-- ============================================================================
-- APPENDIX A2 — Categorical distributions
-- ============================================================================

-- Status — 13 distinct values (a huge influence on D5 grouping)
SELECT COALESCE("Status", '<NULL>') AS value, COUNT(*) AS count
FROM raw.fashionable_sales_raw GROUP BY 1 ORDER BY 2 DESC LIMIT 15;

-- Courier Status — 3 values + NULL. Compare against Status for D6 contradictions.
SELECT COALESCE("Courier Status", '<NULL>') AS value, COUNT(*) AS count
FROM raw.fashionable_sales_raw GROUP BY 1 ORDER BY 2 DESC LIMIT 15;

-- Fulfilment — 2 values. Compare with fulfilled-by (D4) for redundancy proof.
SELECT COALESCE("Fulfilment", '<NULL>') AS value, COUNT(*) AS count
FROM raw.fashionable_sales_raw GROUP BY 1 ORDER BY 2 DESC LIMIT 15;

-- Sales Channel — 2 values, dominated by Fashionable.in.
SELECT COALESCE("Sales Channel", '<NULL>') AS value, COUNT(*) AS count
FROM raw.fashionable_sales_raw GROUP BY 1 ORDER BY 2 DESC LIMIT 15;

-- ship-service-level — 2 values (Expedited / Standard).
SELECT COALESCE("ship-service-level", '<NULL>') AS value, COUNT(*) AS count
FROM raw.fashionable_sales_raw GROUP BY 1 ORDER BY 2 DESC LIMIT 15;

-- Category — 9 values, informs dim_product.
SELECT COALESCE("Category", '<NULL>') AS value, COUNT(*) AS count
FROM raw.fashionable_sales_raw GROUP BY 1 ORDER BY 2 DESC LIMIT 15;

-- Size — 11 values including 'Free', up to 6XL.
SELECT COALESCE("Size", '<NULL>') AS value, COUNT(*) AS count
FROM raw.fashionable_sales_raw GROUP BY 1 ORDER BY 2 DESC LIMIT 15;

-- currency — should be 1 value (INR) + NULLs. Constants get dropped in D4.
SELECT COALESCE("currency", '<NULL>') AS value, COUNT(*) AS count
FROM raw.fashionable_sales_raw GROUP BY 1 ORDER BY 2 DESC LIMIT 15;

-- ship-country — should be 1 value (IN) + NULLs. Constant → drop in D4.
SELECT COALESCE("ship-country", '<NULL>') AS value, COUNT(*) AS count
FROM raw.fashionable_sales_raw GROUP BY 1 ORDER BY 2 DESC LIMIT 15;

-- B2B — should be True/False.
SELECT COALESCE("B2B", '<NULL>') AS value, COUNT(*) AS count
FROM raw.fashionable_sales_raw GROUP BY 1 ORDER BY 2 DESC LIMIT 15;

-- fulfilled-by — NULL vs 'Easy Ship'. Cross-check against Fulfilment for D4.
SELECT COALESCE("fulfilled-by", '<NULL>') AS value, COUNT(*) AS count
FROM raw.fashionable_sales_raw GROUP BY 1 ORDER BY 2 DESC LIMIT 15;

-- Distinct-value counts (one row per column) — quick cardinality sanity check.
SELECT
    COUNT(DISTINCT "Status")              AS status_distinct,
    COUNT(DISTINCT "Courier Status")      AS courier_status_distinct,
    COUNT(DISTINCT "Fulfilment")          AS fulfilment_distinct,
    COUNT(DISTINCT "Sales Channel")       AS sales_channel_distinct,
    COUNT(DISTINCT "ship-service-level")  AS ship_service_level_distinct,
    COUNT(DISTINCT "Category")            AS category_distinct,
    COUNT(DISTINCT "Size")                AS size_distinct,
    COUNT(DISTINCT "currency")            AS currency_distinct,
    COUNT(DISTINCT "ship-country")        AS ship_country_distinct,
    COUNT(DISTINCT "B2B")                 AS b2b_distinct,
    COUNT(DISTINCT "fulfilled-by")        AS fulfilled_by_distinct
FROM raw.fashionable_sales_raw;
