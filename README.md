![Fashionable Analytics Banner](assets/banner.png)

# Fashionable Analytics Assessment

> Transforming a raw eCommerce sales dataset into a production-style analytics warehouse using **DuckDB**, **dbt**, and **Kimball dimensional modeling**.

![Python](https://img.shields.io/badge/Python-3.11-blue)
![dbt](https://img.shields.io/badge/dbt-1.x-orange)
![DuckDB](https://img.shields.io/badge/DuckDB-Analytics-yellow)
![Kimball](https://img.shields.io/badge/Model-Kimball-success)
![Tests](https://img.shields.io/badge/dbt%20Tests-79-success)

---

# Executive Summary

This project demonstrates an end-to-end Analytics Engineering workflow:

- Import raw CSV sales data into DuckDB
- Profile and assess data quality
- Clean and standardize the source using dbt
- Build a Kimball Star Schema
- Validate transformations with automated dbt tests
- Produce BI-ready marts and visualizations

The resulting warehouse enables fast analytical queries by **Product**, **Category**, **Date**, **Geography**, **Order Status**, **Fulfilment**, and **Sales Channel**.

---

# Solution Architecture

```text
                     Fashionable Sales CSV
                              │
                              ▼
                     DuckDB Raw Layer
                              │
                              ▼
               dbt Staging (Cleaning & Validation)
                              │
       ┌───────────┬──────────┴──────────┬────────────────┐
       ▼           ▼                     ▼                ▼
  dim_product   dim_date          dim_geography    dim_order_status
       │           │                     │                │
       └───────────┴───── fct_sales ─────┴────────────────┘
                              │
                              ▼
                        BI & Analytics
```

---

# Star Schema

**Fact Table**

```
fct_sales
```

**Dimensions**

- dim_product
- dim_date
- dim_geography
- dim_order_status

### Fact Grain

> **One row per Order × SKU**

This preserves the lowest business grain, enabling:

- Product analysis
- Style analysis
- Size analysis
- Basket analysis
- Roll-up to order level

---

# Data Quality Highlights

The project performs systematic data-quality validation before modeling.

### Checks

- Duplicate detection
- Missing-value assessment
- Product consistency
- Date validation
- Business-rule validation
- Accepted values
- Relationships
- Uniqueness

### Key Findings

- 128,975 source records
- 6 business-level duplicate rows
- 79 automated dbt tests
- No invalid dates
- No negative quantities or revenue
- Stable SKU → Product relationships

---

# Project Structure

```text
fashionable-analytics-assessment/
│
├── data/
│   └── raw/
│
├── scripts/
│   ├── load_raw.py
│   ├── profile_raw.sql
│   └── build_bi_charts.py
│
├── warehouse/
│
├── dbt/
│   ├── models/
│   │   ├── staging/
│   │   └── marts/
│   ├── seeds/
│   ├── tests/
│   ├── macros/
│   └── profiles.yml
│
├── presentations/
│
├── assets/
│
├── FUTURE_IMPROVEMENTS.md
└── README.md
```

---

# Warehouse Models

| Layer | Model | Description |
|--------|-------|-------------|
| Raw | fashionable_sales_raw | Source CSV |
| Seed | state_to_region | Region lookup |
| Staging | stg_fashionable__orders | Cleaned order lines |
| Mart | dim_product | Product dimension |
| Mart | dim_date | Date dimension |
| Mart | dim_geography | Geography dimension |
| Mart | dim_order_status | Status dimension |
| Mart | fct_sales | Sales fact |

---

# Technology Stack

- Python 3.11
- DuckDB
- dbt
- SQL
- Kimball Dimensional Modeling
- pytest
- Matplotlib

---

# Quick Start

## Install

```bash
pip install -r requirements.txt
```

## Configure dbt

```bash
export DBT_PROJECT_DIR=$PWD/dbt
export DBT_PROFILES_DIR=$PWD/dbt
export DBT_DUCKDB_PATH=$PWD/warehouse/fashionable.duckdb
```

## Build

```bash
python scripts/load_raw.py

dbt deps
dbt seed
dbt build
```

Expected output

```
6 models built
79 tests passed
```

---

# Documentation

Generate dbt documentation

```bash
dbt docs generate
dbt docs serve
```

Includes:

- Model lineage
- Column documentation
- Test coverage
- Dependencies

---

# BI Visualizations

Generate charts

```bash
python scripts/build_bi_charts.py
```

Outputs

```
presentations/charts/
```

The final presentation is available under

```
presentations/final_deck.pptx
```

---

# Example Business Query

```sql
SELECT
    p.product_style,
    SUM(f.quantity) AS units,
    ROUND(SUM(f.revenue_amount),2) AS revenue_inr
FROM marts.fct_sales f
JOIN marts.dim_product p USING(product_key)
JOIN marts.dim_geography g USING(geography_key)
JOIN marts.dim_order_status s USING(status_key)
WHERE g.ship_city='MUMBAI'
AND s.status_group IN ('Delivered','Shipped')
GROUP BY p.product_style
ORDER BY units DESC
LIMIT 5;
```

---

# Additional Documentation

- DATA_QUALITY_STRATEGY.md
- FUTURE_IMPROVEMENTS.md
- final_deck.pptx

---

# Project Deliverables

✅ Raw data ingestion

✅ Data profiling

✅ Data cleaning

✅ Kimball dimensional model

✅ Automated dbt testing

✅ BI-ready marts

✅ Technical documentation

✅ Interview presentation