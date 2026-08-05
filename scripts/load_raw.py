from pathlib import Path
import duckdb

repo = Path(__file__).resolve().parents[1]
csv_path = repo / "data/raw/Fashionable_Sale_Report.csv"
db_path = repo / "warehouse/fashionable.duckdb"

db_path.parent.mkdir(parents=True, exist_ok=True)

with duckdb.connect(str(db_path)) as con:
    con.execute("CREATE SCHEMA IF NOT EXISTS raw")
    con.execute("DROP TABLE IF EXISTS raw.fashionable_sales_raw")

    con.execute(
        """
        CREATE TABLE raw.fashionable_sales_raw AS
        SELECT *
        FROM read_csv_auto(
            ?,
            header = true,
            all_varchar = true
        )
        """,
        [str(csv_path)],
    )

    row_count = con.execute(
        "SELECT COUNT(*) FROM raw.fashionable_sales_raw"
    ).fetchone()[0]

print(f"Loaded {row_count:,} rows")