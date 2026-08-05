# Decisions Log

One paragraph per major trade-off. This is the interview prep sheet — when
asked "why did you do X?", the answer is here.

**Where design decisions live:**
- **Phase 0 — architecture** — this file (below).
- **Phase 1 → 2 — D1–D8 (data-cleaning & modelling choices)** — full rationale
  + interview soundbites are embedded in the speaker notes of
  `presentations/data_profiling.pptx` slide 6. Evidence backing each decision
  lives in `docs/profiling.md`.

## Phase 0 — Setup

### Warehouse: DuckDB via `dbt-duckdb`
Chose DuckDB because the dataset is 129k rows (trivial), it needs zero
infrastructure (single file), and it lets the grader clone-and-run without
credentials or a Docker stack. **Trade-off I'd own in the interview:** DuckDB
gives no real story on role-based access, concurrency, or multi-user
isolation — in production I'd swap the adapter for Snowflake / BigQuery /
Postgres. The dbt project itself is warehouse-agnostic apart from one
adapter dependency, so the swap is small.

### Raw ingestion: Python script, not `dbt seed`
`scripts/load_raw.py` uses DuckDB's native `read_csv_auto` to write
`raw.fashionable_sales_raw`. dbt's `seed` command is technically capable but
is (a) slow on 129k rows and (b) semantically wrong — seeds are for small
static reference data (country codes, mappings), not the main dataset. Using
a load script also mirrors reality: in production an EL tool (Fivetran,
Airbyte, custom) drops raw data into a landing schema, and dbt reads it from
there. Keeping the boundary between "load" and "transform" clean means the
dbt project is portable to any real EL pipeline.

### Raw layer is verbatim (all `VARCHAR`, no renaming)
Loading with `all_varchar=True` means every column arrives as TEXT and
column names keep their original casing/spaces/junk (including `Unnamed: 22`).
This is deliberate: the raw layer is a debuggable mirror of the source file.
The moment we cast or rename, we've committed to an interpretation, which
belongs in staging where it's visible, testable, and reversible.

### Folder structure: `dbt/` sibling to `scripts/` and `data/`
The dbt project sits in its own `dbt/` folder rather than at repo root, so
that non-dbt concerns (raw data, loading scripts, warehouse file, docs) have
their own homes and don't pollute dbt's paths. It also makes it obvious that
dbt is just one component of the pipeline.

### `models/` layout: `staging/<source>/`, `intermediate/`, `marts/<facts|dimensions>/`
- **staging** namespaced by source (`staging/fashionable/`) so adding a
  second source later doesn't require a reshuffle. Convention:
  `stg_<source>__<entity>.sql`.
- **intermediate** for business-logic joins and reshapes that aren't
  themselves marts (kept flat for now — will nest if it grows).
- **marts** split into `dimensions/` and `facts/` — standard Kimball
  convention, makes model purpose obvious at a glance.

### Custom `generate_schema_name` macro
Overrides dbt's default `<target>_<custom>` schema-name concatenation so
that `+schema: staging` in `dbt_project.yml` produces a schema literally
called `staging`. Purely cosmetic — makes the DuckDB explorer readable
(`staging.stg_fashionable__orders` instead of `main_staging.stg_...`) and
matches the medallion terminology used in the README.

### Materialization defaults per layer
- staging & intermediate: `view` — cheap, always fresh, easy to iterate.
- marts: `table` — BI consumers expect stable, performant tables. Would
  revisit as `incremental` in Phase 10 if the fact table grew past a few
  million rows.

### In-repo `profiles.yml`, invoked with explicit `--profiles-dir`
Standard dbt puts `profiles.yml` in `~/.dbt/`, which isn't portable. Keeping
it in `dbt/profiles.yml` and passing `--project-dir dbt --profiles-dir dbt`
on every command makes the project fully self-contained — clone and run,
no home-directory setup. The DuckDB path itself is env-var driven
(`DBT_DUCKDB_PATH`) with a relative-to-CWD default of
`warehouse/fashionable.duckdb`, which works out of the box if you run dbt
from the repo root.

