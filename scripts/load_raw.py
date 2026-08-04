"""Load Fashionable_Sale_Report.csv into DuckDB, verbatim.

Phase 0 promise: the raw layer is a faithful mirror of the source file.
No renaming, no type inference, no filtering. Cleaning happens in dbt staging.

Idempotent: DROP + CREATE, so re-runs are safe.
"""
from __future__ import annotations

import sys
from pathlib import Path

import duckdb

REPO = Path(__file__).resolve().parents[1]
CSV = REPO / "data" / "raw" / "Fashionable_Sale_Report.csv"
DB = REPO / "warehouse" / "fashionable.duckdb"

EXPECTED_ROWS = 128_975


def main() -> int:
    if not CSV.exists():
        print(f"ERROR: source CSV not found at {CSV}", file=sys.stderr)
        return 1

    DB.parent.mkdir(parents=True, exist_ok=True)

    con = duckdb.connect(str(DB))
    con.execute("CREATE SCHEMA IF NOT EXISTS raw")
    con.execute("DROP TABLE IF EXISTS raw.fashionable_sales_raw")
    # all_varchar=True: no silent type coercion. Staging owns typing.
    con.execute(
        f"""
        CREATE TABLE raw.fashionable_sales_raw AS
        SELECT * FROM read_csv_auto(
            '{CSV}',
            header=True,
            all_varchar=True
        )
        """
    )

    n = con.execute("SELECT COUNT(*) FROM raw.fashionable_sales_raw").fetchone()[0]
    cols = [r[0] for r in con.execute("DESCRIBE raw.fashionable_sales_raw").fetchall()]

    print(f"Loaded {n:,} rows into raw.fashionable_sales_raw")
    print(f"Columns ({len(cols)}): {cols}")

    if n != EXPECTED_ROWS:
        print(
            f"WARNING: expected {EXPECTED_ROWS:,} rows, got {n:,}. "
            "Investigate before proceeding to staging.",
            file=sys.stderr,
        )
        # Non-fatal: fail loudly but let the user decide.

    con.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
