"""Clear AlignFlow application data for a fresh local start."""

import argparse
import shutil
from pathlib import Path

import psycopg
from pymongo import MongoClient

from app.main import settings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--confirm", required=True, help="Type RESET-ALIGNFLOW-DATA")
    args = parser.parse_args()
    if args.confirm != "RESET-ALIGNFLOW-DATA":
        parser.error("Confirmation must be RESET-ALIGNFLOW-DATA")

    storage_root = Path(settings.data_dir).resolve()
    uploads = (storage_root / "orders").resolve()
    if uploads.parent != storage_root or storage_root == Path(storage_root.anchor):
        parser.error("Unsafe DATA_DIR path")

    print("PostgreSQL: configured DATABASE_URL")
    print(f"MongoDB database: {settings.mongodb_database}")
    print(f"Uploaded files: {uploads}")

    with psycopg.connect(settings.database_url) as postgres, MongoClient(settings.mongodb_url) as client:
        client.admin.command("ping")
        mongo = client[settings.mongodb_database]
        with postgres.cursor() as cursor:
            cursor.execute("SELECT to_regclass('public.patient_orders')")
            if cursor.fetchone()[0] is None:
                raise RuntimeError("PostgreSQL schema is missing. Run database/setup.sql first.")
        # Clear relational links before resetting MongoDB's order counter.
        with postgres.cursor() as cursor:
            cursor.execute("TRUNCATE TABLE sessions, patient_orders, patients, clinicians, "
                           "clinics, users RESTART IDENTITY CASCADE")
            cursor.execute("INSERT INTO users (username, password, name, role) "
                           "VALUES ('admin', 'admin', 'Admin', 'admin')")
        postgres.commit()

        for collection in ("orders", "counters", "fs.files", "fs.chunks"):
            mongo[collection].delete_many({})
        if uploads.exists():
            shutil.rmtree(uploads)

    print("Reset complete. Sign in with admin / admin and change the password.")


if __name__ == "__main__":
    main()
