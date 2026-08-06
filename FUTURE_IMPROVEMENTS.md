# Future Improvements

The following items were intentionally left out due to the limited project time. They would be added in a production environment.

## CI/CD

* Run `dbt build` automatically on every pull request.
* Block merges when tests fail.
* Add SQL formatting and linting.
* Build only changed models to make CI faster.

## Orchestration

* Run data loading and dbt through Airflow, Dagster, or Prefect.
* Add retries, alerts, and monitoring.
* Replace the CSV loader with a real data ingestion tool such as Fivetran or Airbyte.

## dbt Improvements

* Make the fact table incremental when the dataset becomes large.
* Use snapshots for product and geography history.
* Create reusable macros for repeated cleaning logic.
* Add exposures for dashboards and notebooks.
* Add model contracts to prevent unexpected schema changes.

## Testing and Monitoring

* Add more advanced data-quality tests.
* Add anomaly detection and monitoring.
* Add freshness checks when using a live data source.
* Add unit tests for complex transformations.

## Data Quality

* Create a separate mart for cancelled and rejected orders.
* Enrich geography data using postal codes and coordinates.
* Split promotion IDs into a proper promotion dimension and bridge table.
* Improve state-name matching to reduce `Unknown` regions.
* Duplicate resolution:** For duplicate `(order_id, sku)` rows, staging keeps the row with a non-null `Amount`, then the latest `_source_index`. In production, I would add clear status priorities, alerts for new conflicts, and a resolution reason for auditability.


## Documentation

* Generate a complete data dictionary.
* Create Architecture Decision Records for important design choices.

## Warehouse and Security

* Move from DuckDB to Snowflake, BigQuery, or Redshift.
* Add separate roles and permissions for different users.

## BI and Semantic Layer

* Connect marts to a BI tool such as Looker, Metabase, or Superset.
* Define metrics such as revenue in one semantic layer.
* Add dbt exposures to show which dashboards use each model.
