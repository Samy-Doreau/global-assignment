#!/usr/bin/env python3
"""pipeline.py : simple end-to-end pipeline orchestrator

Steps:
1. Truncate raw tables if they exist
2. Seed CSVs via dbt (users, episodes)
3. Load JSONL events via loader script
4. Run dbt models & tests
5. Build Elementary monitoring models & generate HTML observability report
6. Export mart views to CSV locally under data/exports/

Run:
    python scripts/pipeline.py --events data/event_logs.json

This is intentionally lightweight and avoids Airflow / Prefect overhead.
"""
import argparse
import os
import subprocess
from pathlib import Path
import psycopg2

RAW_TABLES = ["raw_users", "raw_episodes", "raw_event_files"]
MARTS = [
    ("mart_top_episodes", "data/exports/mart_top_episodes.csv"),
    ("mart_user_session_metrics", "data/exports/mart_user_session_metrics.csv"),
]

BASE_DIR = Path(__file__).resolve().parent.parent
DBT_DIR = BASE_DIR / "dbt"


def run_cmd(cmd: str):
    print(f"→ {cmd}")
    subprocess.run(cmd, shell=True, check=True)


def get_connection():
    return psycopg2.connect(
        host=os.getenv("POSTGRES_HOST", "localhost"),
        port=os.getenv("POSTGRES_PORT", "5432"),
        dbname=os.getenv("POSTGRES_DB", "podcast_analytics"),
        user=os.getenv("POSTGRES_USER", "podcast"),
        password=os.getenv("POSTGRES_PASSWORD", "podcast"),
    )


def truncate_raw_tables():
    print("⌛ Truncating raw tables …")
    with get_connection() as conn, conn.cursor() as cur:
        for tbl in RAW_TABLES:
            try:
                cur.execute(f"TRUNCATE TABLE {tbl};")
            except psycopg2.errors.UndefinedTable:
                print(f"  Table {tbl} doesn't exist yet, skipping")
    print("✅ Raw tables truncated")


def export_marts():
    out_dir = BASE_DIR / "data" / "exports"
    out_dir.mkdir(parents=True, exist_ok=True)
    with get_connection() as conn, conn.cursor() as cur:
        for mart, path in MARTS:
            path = Path(path)
            print(f"📤 Exporting {mart} → {path}")
            with path.open("w") as fp:
                cur.copy_expert(f"COPY (SELECT * FROM {mart}) TO STDOUT WITH CSV HEADER", fp)


def main():
    parser = argparse.ArgumentParser(description="Run full local pipeline")
    parser.add_argument("--events", required=True, help="Path to JSONL events file")
    args = parser.parse_args()

    events_path = Path(args.events).resolve()
    if not events_path.exists():
        raise FileNotFoundError(events_path)

    truncate_raw_tables()

    # Step 2: dbt seed
    run_cmd(f"cd {DBT_DIR} && dbt seed --profiles-dir ..")

    # Step 3: load events
    run_cmd(f"python scripts/load_events_to_postgres.py --file {events_path}")

    # Step 4: dbt deps+run+test
    run_cmd(f"cd {DBT_DIR} && dbt deps --profiles-dir .. && dbt run --profiles-dir .. && dbt test --profiles-dir ..")

    # Step 5: Elementary – build monitoring tables & generate report
    # The first command materializes Elementary models (schema, logs tables).
    # The second command produces an HTML report (dbt/edr_target/elementary_report.html)
    run_cmd(f"cd {DBT_DIR} && dbt run --profiles-dir .. --select elementary")
    run_cmd(f"cd {DBT_DIR} && edr report --profiles-dir ..")

    # Step 6: export marts
    export_marts()
    print("🏁 Pipeline completed successfully – observability report available at dbt/edr_target/elementary_report.html")


if __name__ == "__main__":
    main() 