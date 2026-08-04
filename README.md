# Fashionable Analytics — Kimball Star Schema Assessment

A dbt project that transforms a raw eCommerce sales export
(`Fashionable_Sale_Report.csv`, ~129k rows) into a Kimball-style dimensional
model for marketing analytics — sales performance by style/category,
geography, time, and order/fulfilment status.

## Architecture at a glance

Two-tool split, one warehouse:

```
CSV  ──(scripts/load_raw.py)──▶  DuckDB raw.fashionable_sales_raw
                                           │
                                           ▼
                                   dbt: staging  (bronze→silver: types, renames, dedupe)
                                           │
                                           ▼
                                   dbt: intermediate (business logic joins)
                                           │
                                           ▼
                                   dbt: marts (gold: dim_* / fct_* star schema)
```

Everything from `raw` onward is dbt. See `DECISIONS.md` for the reasoning.

## Layout

```
fashionable-analytics-assessment/
├── data/raw/                Source CSV, checked in for reproducibility
├── scripts/load_raw.py      Loads CSV → raw.fashionable_sales_raw (verbatim)
├── warehouse/               DuckDB file lives here (gitignored)
├── dbt/
│   ├── dbt_project.yml      Layer defaults: staging=view, marts=table
│   ├── profiles.yml         In-repo, portable (DBT_DUCKDB_PATH env var)
│   ├── macros/
│   │   └── generate_schema_name.sql   Clean schema names (no target_ prefix)
│   └── models/
│       ├── staging/fashionable/       stg_fashionable__*
│       ├── intermediate/              int_fashionable__*
│       └── marts/
│           ├── dimensions/            dim_*
│           └── facts/                 fct_*
├── Makefile                 One-command entry points (see `make help`)
├── requirements.txt
├── DECISIONS.md             Running log of trade-offs (interview prep)
└── FUTURE_IMPROVEMENTS.md   What I'd add given more time / for production
```

## Quickstart

Prereqs: `pyenv` with 3.11.13 installed, `make`.

```bash
make install      # creates .venv, pip installs dbt-duckdb
make deps         # dbt deps (dbt_utils)
make load         # CSV → raw.fashionable_sales_raw
make debug        # verify dbt connection
make build        # run + test all models
make docs         # generate + serve docs at http://localhost:8080
```

Nothing is global — everything lives under this repo.

## Current status

Phase 0 complete: raw CSV loaded verbatim into DuckDB, dbt scaffolded,
`fashionable` source declared. Transformations begin in Phase 2.
