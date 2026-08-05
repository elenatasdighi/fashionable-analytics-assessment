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
├── requirements.txt
├── DECISIONS.md             Running log of trade-offs (interview prep)
└── FUTURE_IMPROVEMENTS.md   What I'd add given more time / for production
```

## Quickstart

Prereqs: `pyenv` with 3.11.13 installed.

**One-time setup** (creates local `.venv` — nothing global):
```bash
PYENV_VERSION=3.11.13 python -m venv .venv
.venv/bin/pip install --index-url https://pypi.org/simple/ -r requirements.txt
```

**Activate the venv** for the rest of the session — makes `python` and `dbt`
resolve to the ones inside `.venv/`:
```bash
source .venv/bin/activate
```

**Load the raw CSV into DuckDB** (idempotent, safe to re-run):
```bash
python scripts/load_raw.py
```

**Run dbt** — all commands need `--project-dir` and `--profiles-dir` because
`profiles.yml` lives in-repo (portable, no `~/.dbt/` setup required):
```bash
dbt deps  --project-dir dbt --profiles-dir dbt
dbt debug --project-dir dbt --profiles-dir dbt
dbt run   --project-dir dbt --profiles-dir dbt
dbt test  --project-dir dbt --profiles-dir dbt
dbt build --project-dir dbt --profiles-dir dbt   # = run + test
dbt docs generate --project-dir dbt --profiles-dir dbt
dbt docs serve    --project-dir dbt --profiles-dir dbt
```

**DuckDB is single-writer.** Any `python scripts/load_raw.py`, `dbt run`, or
`dbt build` fails with a "Conflicting lock" error if DBeaver has the
warehouse file open. Disconnect DBeaver before writes; reads
(`read_only=True` in Python, DBeaver SELECTs) can coexist.

## Current status

Phase 0 complete: raw CSV loaded verbatim into DuckDB, dbt scaffolded,
`fashionable` source declared. Transformations begin in Phase 2.
