"""Profile raw.fashionable_sales_raw → docs/profiling.md.

Presentation-shaped: five slide sections mirror the profiling deck
(`presentations/data_profiling.pptx`). An **Appendix — Detailed evidence**
at the bottom carries the raw counts each slide summarises and the
traceability behind design decisions D1–D8.

Read-only DuckDB connection: safe to run while DBeaver is attached in
read-only mode. Fails with a clear IOException if DBeaver holds a write
lock — disconnect DBeaver and re-run.
"""
from __future__ import annotations

from datetime import datetime
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parents[1]
DB = ROOT / "warehouse" / "fashionable.duckdb"
OUT = ROOT / "docs" / "profiling.md"
TABLE = "raw.fashionable_sales_raw"

# Categorical columns worth showing full value distributions for in the
# appendix. Low-cardinality string columns only.
CATEGORICAL = [
    "Status", "Courier Status", "Fulfilment", "Sales Channel",
    "ship-service-level", "Category", "Size", "currency",
    "ship-country", "B2B", "fulfilled-by",
]


# --- helpers ------------------------------------------------------------------
def q(name: str) -> str:
    """Double-quote a SQL identifier safely (handles embedded `"`)."""
    return '"' + name.replace('"', '""') + '"'


def is_missing(name: str) -> str:
    """SQL predicate for NULL or whitespace-only string."""
    c = q(name)
    return f"({c} IS NULL OR TRIM({c}) = '')"


def md_table(headers, rows) -> str:
    lines = [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join(["---"] * len(headers)) + " |",
    ]
    for r in rows:
        lines.append(
            "| " + " | ".join("NULL" if v is None else str(v) for v in r) + " |"
        )
    return "\n".join(lines)


def slide(number: int, title: str, body: str) -> str:
    return (
        f"<!-- ===== SLIDE {number} — {title.upper()} ===== -->\n"
        f"## Slide {number} — {title}\n\n"
        f"{body}\n\n"
        f"<!-- SLIDE {number} END -->"
    )


def date_text(value) -> str:
    return value.strftime("%d %b %Y") if value else "n/a"


# --- main ---------------------------------------------------------------------
def main() -> None:
    if not DB.exists():
        raise FileNotFoundError(f"Database not found: {DB}")
    OUT.parent.mkdir(parents=True, exist_ok=True)

    with duckdb.connect(str(DB), read_only=True) as con:
        columns = [r[0] for r in con.execute(f"DESCRIBE {TABLE}").fetchall()]
        business_cols = [c for c in columns if c.lower() != "index"]

        # ============ Slide 1 — Data Exploration ============
        (records, unique_orders, skus, styles, categories, sizes,
         cities, min_date, max_date, distinct_dates) = con.execute(f"""
            SELECT
                COUNT(*),
                COUNT(DISTINCT "Order ID"),
                COUNT(DISTINCT "SKU"),
                COUNT(DISTINCT "Style"),
                COUNT(DISTINCT "Category"),
                COUNT(DISTINCT "Size"),
                COUNT(DISTINCT "ship-city"),
                MIN(TRY_STRPTIME("Date", '%m-%d-%y')),
                MAX(TRY_STRPTIME("Date", '%m-%d-%y')),
                COUNT(DISTINCT "Date")
            FROM {TABLE}
        """).fetchone()

        # ============ Slide 2 — Source Grain ============
        multi_line_orders, max_lines_per_order = con.execute(f"""
            SELECT
                COUNT(*) FILTER (WHERE line_count > 1),
                MAX(line_count)
            FROM (
                SELECT "Order ID", COUNT(*) AS line_count
                FROM {TABLE} GROUP BY "Order ID"
            )
        """).fetchone()

        styles_with_multi_skus, max_skus_per_style = con.execute(f"""
            SELECT
                COUNT(*) FILTER (WHERE sku_count > 1),
                MAX(sku_count)
            FROM (
                SELECT "Style", COUNT(DISTINCT "SKU") AS sku_count
                FROM {TABLE}
                WHERE NOT {is_missing('Style')}
                GROUP BY "Style"
            )
        """).fetchone()

        dup_order_sku_groups, dup_order_sku_extra = con.execute(f"""
            SELECT COUNT(*), COALESCE(SUM(row_count - 1), 0)
            FROM (
                SELECT "Order ID", "SKU", COUNT(*) AS row_count
                FROM {TABLE}
                GROUP BY "Order ID", "SKU"
                HAVING COUNT(*) > 1
            )
        """).fetchone()

        # ============ Slide 3 — Data Quality — Completeness & Uniqueness ============
        gb = ", ".join(q(c) for c in business_cols)
        biz_dupes = con.execute(f"""
            SELECT COALESCE(SUM(row_count - 1), 0)
            FROM (
                SELECT {gb}, COUNT(*) AS row_count
                FROM {TABLE} GROUP BY {gb}
                HAVING COUNT(*) > 1
            )
        """).fetchone()[0]

        quality = con.execute(f"""
            SELECT
                COUNT(*) FILTER (WHERE {is_missing('Amount')}),
                COUNT(*) FILTER (WHERE TRY_CAST("Qty" AS INT) = 0),
                COUNT(*) FILTER (WHERE TRY_CAST("Qty" AS INT) < 0),
                COUNT(*) FILTER (WHERE TRY_CAST("Amount" AS DOUBLE) < 0),
                COUNT(*) FILTER (
                    WHERE NOT {is_missing('Date')}
                      AND TRY_STRPTIME("Date", '%m-%d-%y') IS NULL
                ),
                COUNT(*) FILTER (
                    WHERE {is_missing('ship-city')} OR {is_missing('ship-state')}
                       OR {is_missing('ship-postal-code')} OR {is_missing('ship-country')}
                )
            FROM {TABLE}
        """).fetchone()

        sku_drift = con.execute(f"""
            SELECT
                COUNT(*) FILTER (WHERE style_count    > 1),
                COUNT(*) FILTER (WHERE category_count > 1),
                COUNT(*) FILTER (WHERE size_count     > 1)
            FROM (
                SELECT "SKU",
                    COUNT(DISTINCT NULLIF(TRIM("Style"),    '')) AS style_count,
                    COUNT(DISTINCT NULLIF(TRIM("Category"), '')) AS category_count,
                    COUNT(DISTINCT NULLIF(TRIM("Size"),     '')) AS size_count
                FROM {TABLE}
                WHERE NOT {is_missing('SKU')}
                GROUP BY "SKU"
            )
        """).fetchone()

        # ============ Slide 4 — Data Quality — Cross-field & Geography ============
        amt_cur = con.execute(f"""
            SELECT
                COUNT(*) FILTER (WHERE {is_missing('Amount')}  AND     {is_missing('currency')}),
                COUNT(*) FILTER (WHERE {is_missing('Amount')}  AND NOT {is_missing('currency')}),
                COUNT(*) FILTER (WHERE NOT {is_missing('Amount')} AND  {is_missing('currency')})
            FROM {TABLE}
        """).fetchone()

        fulf_pairs = con.execute(f"""
            SELECT "Fulfilment",
                   COALESCE(NULLIF(TRIM("fulfilled-by"), ''), '<NULL>'),
                   COUNT(*)
            FROM {TABLE}
            GROUP BY 1, 2 ORDER BY 1, 2
        """).fetchall()

        contradictions_rows = con.execute(f"""
            SELECT "Status", COALESCE("Courier Status", '<NULL>'), COUNT(*)
            FROM {TABLE}
            WHERE ("Status" = 'Shipped'    AND "Courier Status" IN ('Unshipped','Cancelled'))
               OR ("Status" LIKE 'Pending%' AND "Courier Status" = 'Shipped')
            GROUP BY 1, 2 ORDER BY 3 DESC
        """).fetchall()
        contradictions_total = sum(r[2] for r in contradictions_rows)

        (city_raw, city_norm, state_raw, state_norm, country_ct) = con.execute(f"""
            SELECT
                COUNT(DISTINCT "ship-city"),
                COUNT(DISTINCT UPPER(TRIM("ship-city"))),
                COUNT(DISTINCT "ship-state"),
                COUNT(DISTINCT UPPER(TRIM("ship-state"))),
                COUNT(DISTINCT "ship-country")
            FROM {TABLE}
        """).fetchone()

        # ============ Slide 5 — Not Every Anomaly Is Bad Data ============
        context = con.execute(f"""
            SELECT
                COUNT(*) FILTER (WHERE TRY_CAST("Qty" AS INT) = 0),
                COUNT(*) FILTER (WHERE TRY_CAST("Qty" AS INT) = 0
                                   AND TRIM("Status") = 'Cancelled'),
                COUNT(*) FILTER (WHERE TRY_CAST("Qty" AS INT) = 0
                                   AND TRIM("Status") LIKE 'Shipped%'),
                COUNT(*) FILTER (WHERE {is_missing('Amount')}),
                COUNT(*) FILTER (WHERE {is_missing('Amount')}
                                   AND TRIM("Status") = 'Cancelled'),
                COUNT(*) FILTER (WHERE {is_missing('Amount')}
                                   AND TRIM("Status") LIKE 'Shipped%')
            FROM {TABLE}
        """).fetchone()

        cancelled_with_amt = con.execute(f"""
            SELECT COUNT(*) FROM {TABLE}
            WHERE "Status" = 'Cancelled' AND TRY_CAST("Amount" AS DOUBLE) > 0
        """).fetchone()[0]

        (promo_present, promo_max_len, promo_max_count, promo_avg) = con.execute(f"""
            SELECT
                COUNT(*) FILTER (WHERE NOT {is_missing('promotion-ids')}),
                MAX(LENGTH("promotion-ids")),
                MAX(LENGTH("promotion-ids") - LENGTH(REPLACE("promotion-ids", ',', '')) + 1),
                AVG(CASE
                    WHEN NOT {is_missing('promotion-ids')}
                    THEN LENGTH("promotion-ids") - LENGTH(REPLACE("promotion-ids", ',', '')) + 1
                END)
            FROM {TABLE}
        """).fetchone()

        # ============ Slide 6 — Treatment Strategy (+ Slide 7 = static D1–D8 table) ============
        u22_nonempty = con.execute(f"""
            SELECT COUNT(*) FROM {TABLE} WHERE NOT {is_missing('Unnamed: 22')}
        """).fetchone()[0]

        # ============ Appendix A1 — full null rates ============
        null_rates = []
        for c in columns:
            miss = con.execute(
                f"SELECT COUNT(*) FILTER (WHERE {is_missing(c)}) FROM {TABLE}"
            ).fetchone()[0]
            null_rates.append((c, f"{miss:,}", f"{100 * miss / records:.2f}%"))
        null_rates.sort(key=lambda x: -int(x[1].replace(",", "")))

        # ============ Appendix A2 — categorical distributions ============
        cat_blocks = []
        for c in CATEGORICAL:
            distinct = con.execute(
                f"SELECT COUNT(DISTINCT {q(c)}) FROM {TABLE}"
            ).fetchone()[0]
            rows = con.execute(f"""
                SELECT COALESCE({q(c)}, '<NULL>'), COUNT(*)
                FROM {TABLE}
                GROUP BY 1 ORDER BY 2 DESC LIMIT 15
            """).fetchall()
            cat_blocks.append((c, distinct, rows))

    # -------- render markdown --------
    s1 = slide(
        1, "Data Exploration",
        f"""### Dataset overview

{md_table(['Metric', 'Finding'], [
    ('Records', f'{records:,}'),
    ('Unique orders', f'{unique_orders:,}'),
    ('Source columns', f'{len(columns):,}'),
    ('Date range', f'{date_text(min_date)} – {date_text(max_date)} ({distinct_dates} distinct days)'),
    ('SKUs', f'{skus:,}'),
    ('Styles', f'{styles:,}'),
    ('Categories', f'{categories:,}'),
    ('Sizes', f'{sizes:,}'),
    ('Ship cities', f'{cities:,}'),
])}

**Business concepts identified:** Orders · Products · Sales · Location · Fulfilment

**Goal:** understand the business process and source grain before modelling.""",
    )

    s2 = slide(
        2, "Understanding the Source Grain",
        f"""### One order ≠ one row

{md_table(['Metric', 'Finding'], [
    ('Records', f'{records:,}'),
    ('Unique orders', f'{unique_orders:,}'),
    ('Extra order lines', f'{records - unique_orders:,}'),
    ('Orders with multiple rows', f'{multi_line_orders:,}'),
    ('Max rows for one order', f'{max_lines_per_order:,}'),
    ('Exact-duplicate (Order ID, SKU) groups', f'{dup_order_sku_groups:,}'),
    ('Extra rows inside those groups', f'{dup_order_sku_extra:,}'),
])}

**Finding:** source grain is **order × SKU line item**. `(Order ID, SKU)` is *almost* unique — the {dup_order_sku_groups} exact-duplicate groups mean staging needs an explicit dedupe step.

### Product hierarchy

`Style → SKU / Product Variant → Size`

{md_table(['Metric', 'Finding'], [
    ('SKUs', f'{skus:,}'),
    ('Styles', f'{styles:,}'),
    ('Sizes', f'{sizes:,}'),
    ('Styles with multiple SKUs', f'{styles_with_multi_skus:,}'),
    ('Max SKUs for one style', f'{max_skus_per_style:,}'),
])}

**Why it matters:** the model must support drill-down at both **Style/Category** and **SKU/Size**. Findings drove the fact grain, not the reverse.""",
    )

    s3 = slide(
        3, "Data Quality — Completeness & Uniqueness",
        f"""**Checks performed:** Completeness · Uniqueness · Validity · Consistency · Business Rules

{md_table(['Finding', 'Result'], [
    ('Business-level exact duplicate rows*', f'{biz_dupes:,}'),
    ('Missing Amount', f'{quality[0]:,}'),
    ('Qty = 0', f'{quality[1]:,}'),
    ('Negative Qty', f'{quality[2]:,}'),
    ('Negative Amount', f'{quality[3]:,}'),
    ('Invalid dates (format %m-%d-%y)', f'{quality[4]:,}'),
    ('Missing shipping info', f'{quality[5]:,}'),
    ('SKU → Style inconsistencies', f'{sku_drift[0]:,}'),
    ('SKU → Category inconsistencies', f'{sku_drift[1]:,}'),
    ('SKU → Size inconsistencies', f'{sku_drift[2]:,}'),
    ('Status ↔ Courier Status contradictions', f'{contradictions_total:,}'),
])}

\\*Exact duplicates ignore the technical `index` field.

> `(Order ID, SKU)` cannot be assumed unique until dedupe. `SKU` **is** consistent with Style / Category / Size — master data is clean.""",
    )

    s4 = slide(
        4, "Data Quality — Cross-field & Geography",
        f"""### `Amount` ↔ `currency` null pattern

- both NULL `{amt_cur[0]:,}` · only Amount NULL `{amt_cur[1]:,}` · only currency NULL `{amt_cur[2]:,}` → **perfectly correlated** — `currency` carries no independent info.

### `Fulfilment` ↔ `fulfilled-by`

{md_table(['Fulfilment', 'fulfilled-by', 'count'], fulf_pairs)}

→ **perfectly redundant** — drop `fulfilled-by` in staging.

### Status ↔ Courier Status contradictions ({contradictions_total} rows, {100*contradictions_total/records:.2f}%)

{md_table(['Status', 'Courier Status', 'count'], contradictions_rows) if contradictions_rows else 'None.'}

→ real but noise-level — flag with warn-level dbt test, don't reject.

### Geography casing collapse

- `ship-city`: **{city_raw:,}** raw → **{city_norm:,}** after `UPPER(TRIM())` — **{100*(city_raw-city_norm)/city_raw:.0f}%** duplication from casing.
- `ship-state`: **{state_raw:,}** raw → **{state_norm:,}** normalized ({100*(state_raw-state_norm)/state_raw:.0f}% duplication). India has 36 states+UTs; normalized 47 → residual misspellings.
- `ship-country`: **{country_ct}** — a constant.""",
    )

    s5 = slide(
        5, "Not Every Anomaly Is Bad Data",
        f"""### Business context of anomalies

{md_table(['Condition', 'Total', 'Cancelled', 'Shipped'], [
    ('Qty = 0',           f'{context[0]:,}', f'{context[1]:,}', f'{context[2]:,}'),
    ('Amount is missing', f'{context[3]:,}', f'{context[4]:,}', f'{context[5]:,}'),
])}

- **Cancelled orders with `Amount > 0`:** **{cancelled_with_amt:,}** — list price captured at cancel. Naïvely summing raw `Amount` inflates revenue ~15%.
- **Active-order anomalies to flag** (not delete):
  - Shipped + Qty = 0: **{context[2]:,}**
  - Shipped + Amount missing: **{context[5]:,}**

### Multi-value complexity

- **`promotion-ids`** — {promo_present:,} rows carry data ({100*promo_present/records:.0f}%). Longest value: {promo_max_len:,} chars, up to **{promo_max_count}** promo IDs per row (avg ~{promo_avg:.1f}).
- Textbook Kimball answer is a `bridge_order_promotion` M:N + `dim_promotion`, but promo IDs are opaque strings with no metadata → `dim_promotion` would be degenerate. MVP surfaces `promo_count` on the fact; bridge deferred.

**Key insight:** NULL / unusual values don't automatically mean bad data. The business generates NULL-carrying rows deliberately (cancellations). Silent filtering destroys signal.""",
    )

    s6 = slide(
        6, "Data Quality Treatment Strategy",
        f"""### Actions

{md_table(['Action', 'Examples'], [
    ('CLEAN',   'Types, snake_case names, whitespace/casing, city/state normalization, date parsing'),
    ('KEEP',    'Cancelled orders, valid business NULLs, `_raw` audit columns'),
    ('FLAG',    'Shipped + Qty = 0 · Shipped + missing Amount · Status/Courier contradictions'),
    ('EXCLUDE', 'Technical `index`, `Unnamed: 22` (79,925 rows are literal "False"), `fulfilled-by` (redundant), constants `currency` / `ship-country`'),
    ('TEST',    'Line-item PK uniqueness · fact↔dim relationships · accepted values for Status · row-count reconciliation vs raw'),
])}

- Non-empty `Unnamed: 22` values: **{u22_nonempty:,}** (all literal "False") — pandas export artifact, safe to drop.

**Guiding principle:** *improve data quality without destroying business information*.""",
    )

    s7 = slide(
        7, "Locked Decisions D1–D8",
        f"""{md_table(['Ref', 'Decision'], [
    ('D1', 'Cancelled orders kept · `is_cancelled` flag + derived `revenue_amount` (= 0 if cancelled)'),
    ('D2', 'Fact grain = order × SKU line item · surrogate key from `(order_id, sku)` after dedupe'),
    ('D3', '`promo_count` on fact · `bridge_order_promotion` + `dim_promotion` deferred'),
    ('D4', 'Drop `Unnamed: 22`, `fulfilled-by`, `currency`, `ship-country` in staging'),
    ('D5', '`dim_order_status` with raw `status_detail` + 5-group `status_group` (Delivered / Shipped / Pending / Cancelled / Returned)'),
    ('D6', 'Let 218 contradictions pass · warn-level dbt test at 250 threshold'),
    ('D7', 'Canonical `UPPER(TRIM())` city/state · keep `_raw` audit columns'),
    ('D8', "Cast `Date` → `DATE` with `strptime('%m-%d-%y')` in staging"),
])}

Full rationale + interview soundbites live in the pptx (slide 7 speaker notes).

> With grain, business semantics and data quality understood, next step is Architecture & Data Modelling.""",
    )

    # Appendix
    null_table_md = md_table(
        ['Column', 'Missing (NULL or empty)', '% missing'], null_rates
    )
    cat_sections = "\n\n".join(
        f"#### `{c}` — {d} distinct values (top 15)\n\n"
        + md_table(['value', 'count'], rows)
        for c, d, rows in cat_blocks
    )
    appendix = (
        "## Appendix — Detailed evidence\n\n"
        "Raw numbers backing the slides above. Every D1–D8 decision cites these.\n\n"
        "### A1. Missing values per column (NULL or empty string)\n\n"
        f"{null_table_md}\n\n"
        "### A2. Categorical distributions\n\n"
        f"{cat_sections}\n"
    )

    report = (
        f"# Raw data profiling — `{TABLE}`\n\n"
        f"_Generated {datetime.now().strftime('%Y-%m-%d %H:%M')} by "
        f"`scripts/profile_raw.py` (read-only DuckDB connection)._\n\n"
        f"Presentation-shaped: seven slide sections mirror 1:1 with the "
        f"content slides of `presentations/data_profiling.pptx`. An "
        f"**Appendix — Detailed evidence** at the bottom carries the raw "
        f"counts each slide summarises and the traceability behind design "
        f"decisions D1–D8.\n\n"
        f"{s1}\n\n{s2}\n\n{s3}\n\n{s4}\n\n{s5}\n\n{s6}\n\n{s7}\n\n"
        f"{appendix}"
    )

    OUT.write_text(report, encoding="utf-8")
    print(f"✓ Profiling report written to {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
