# Future Improvements

Things intentionally out of scope for the 4–6h build, with a note on *why*
they matter — so the interview answer to "what would you add for production?"
comes straight from here.

## CI / CD
- GitHub Actions workflow: `pip install -r requirements.txt`, `dbt deps`,
  `dbt build`, `dbt docs generate`, upload artifacts. Guard main with
  passing tests as a merge check.
- `sqlfmt` + `sqlfluff` for style enforcement.
- Slim CI: only rebuild changed models on PRs (`dbt build --select state:modified+`
  with a state artifact from main).

## Orchestration
- Wrap `load_raw.py` + `dbt build` in Airflow / Dagster / Prefect with proper
  retry, alerting, and lineage. For an EL-real setup, replace the CSV script
  with a Fivetran/Airbyte connector into `raw.*` tables.

## dbt patterns
- **Incremental models** on the fact table once row count justifies it
  (probably >5M rows). Merge on `(order_id, sku)` grain.
- **Snapshots** on the product dimension if slowly-changing attributes matter
  (category re-classification, size re-mapping).
- **More macros**: e.g. `clean_string()` for city/state normalization,
  `parse_promotion_ids()` for the multi-value column — used consistently
  wherever the pattern appears.
- **Exposures**: declare the BI dashboards / notebooks that consume the marts
  so lineage extends past the warehouse.
- **Contracts** on marts models — enforced column types and constraints, so
  a breaking schema change fails at build time rather than at BI time.

## Testing
- **dbt-expectations** package for distributional tests (row count within
  bounds, column mean within bounds, no unexpected new values).
- **Elementary** for anomaly detection + a lightweight data-observability UI.
- **Freshness monitors** once the CSV is replaced with a live feed.
- **Unit tests** (`dbt` 1.8+) on tricky transformations — e.g. the
  `promotion-ids` explode-and-dedupe logic.

## Data quality
- Split cancelled / rejected orders into their own downstream mart so main
  fact represents only revenue-relevant transactions, with a clear
  `is_cancelled` boolean surfaced instead of dropped silently.
- Address / geography enrichment: postal-code → lat/lng, state → region.
- Deduping the `promotion-ids` blob into a proper `bridge_order_promotion`
  table (M:N bridge from fact to a `dim_promotion`).

## Documentation
- A proper data dictionary generated from `schema.yml` (script or use
  `dbt-docs` catalog export).
- ADRs (Architecture Decision Records) for the biggest calls — grain of
  the fact, cancelled-order treatment, promotion bridge — instead of the
  flat `DECISIONS.md`.

## Warehouse
- Swap DuckDB for the production warehouse (Snowflake / BigQuery /
  Redshift). dbt project is 95% adapter-portable; profile change plus any
  vendor-specific SQL (window functions, JSON functions) to review.
- Role/permission model: separate `raw_reader`, `analyst`, `bi_read` roles.

## BI
- Publish marts to a proper BI tool (Looker / Metabase / Superset) with
  a semantic layer defined once, rather than in each dashboard.
