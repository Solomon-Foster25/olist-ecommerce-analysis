"""
Load the Olist Brazilian E-Commerce CSVs into a single SQLite database (olist.db).

Usage:
    1. Put this script in the same folder as the unzipped Kaggle CSVs
       (or pass the folder path as an argument).
    2. pip install pandas
    3. python load_data.py            # or: python load_data.py path/to/csv_folder

Afterwards, open olist.db in DB Browser for SQLite (free) or any SQL tool
and start running the queries in analysis.sql.
"""

import sqlite3
import sys
from pathlib import Path

import pandas as pd

CSV_DIR = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
DB_PATH = Path("olist.db")

# CSV file name -> table name in the database
TABLES = {
    "olist_customers_dataset.csv": "customers",
    "olist_orders_dataset.csv": "orders",
    "olist_order_items_dataset.csv": "order_items",
    "olist_order_payments_dataset.csv": "order_payments",
    "olist_order_reviews_dataset.csv": "order_reviews",
    "olist_products_dataset.csv": "products",
    "olist_sellers_dataset.csv": "sellers",
    "olist_geolocation_dataset.csv": "geolocation",
    "product_category_name_translation.csv": "category_translation",
}

# Indexes on the join keys keep queries fast
INDEXES = [
    ("orders", "order_id"),
    ("orders", "customer_id"),
    ("customers", "customer_id"),
    ("customers", "customer_unique_id"),
    ("order_items", "order_id"),
    ("order_items", "product_id"),
    ("order_items", "seller_id"),
    ("order_payments", "order_id"),
    ("order_reviews", "order_id"),
    ("products", "product_id"),
    ("sellers", "seller_id"),
]


def main() -> None:
    missing = [f for f in TABLES if not (CSV_DIR / f).exists()]
    if missing:
        print("Couldn't find these files in", CSV_DIR.resolve())
        for f in missing:
            print("  -", f)
        sys.exit(1)

    with sqlite3.connect(DB_PATH) as conn:
        for csv_name, table in TABLES.items():
            # utf-8-sig strips the byte-order mark some of these files have
            df = pd.read_csv(CSV_DIR / csv_name, encoding="utf-8-sig")
            df.to_sql(table, conn, if_exists="replace", index=False)
            print(f"{table:<22} {len(df):>9,} rows")

        for table, col in INDEXES:
            conn.execute(f"CREATE INDEX IF NOT EXISTS idx_{table}_{col} ON {table}({col})")

    print(f"\nDone. Database written to {DB_PATH.resolve()}")


if __name__ == "__main__":
    main()
