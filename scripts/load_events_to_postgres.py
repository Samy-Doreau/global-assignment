#!/usr/bin/env python3
"""load_events_to_postgres.py : load JSONL events into a Postgres table

Usage:
    python load_events_to_postgres.py --file data/event_logs.jsonl --table raw_event_files
"""
import argparse
import json
import os
from pathlib import Path
import psycopg2
import psycopg2.extras as extras


DEFAULT_TABLE = "raw_event_files"


def get_connection():
    conn = psycopg2.connect(
        host=os.getenv("POSTGRES_HOST", "localhost"),
        port=os.getenv("POSTGRES_PORT", "5432"),
        dbname=os.getenv("POSTGRES_DB", "podcast_analytics"),
        user=os.getenv("POSTGRES_USER", "podcast"),
        password=os.getenv("POSTGRES_PASSWORD", "podcast"),
    )
    conn.autocommit = True
    return conn


def ensure_table(conn, table):
    with conn.cursor() as cur:
        cur.execute(
            f"""
            create table if not exists {table} (
                data jsonb not null,
                source_file_loaded_at timestamptz default now(),
                source_file_name text
            );
            """
        )


def load_file(conn, file_path: Path, table: str):
    with file_path.open() as fp:
        rows = [(line, file_path.name) for line in fp if line.strip()]

    with conn.cursor() as cur:
        extras.execute_batch(
            cur,
            f"insert into {table} (data, source_file_name) values (%s, %s)",
            rows,
            page_size=1000,
        )
    print(f"Loaded {len(rows)} rows into {table}")


def main():
    parser = argparse.ArgumentParser(description="Load events JSONL into Postgres")
    parser.add_argument("--file", required=True, type=Path, help="Path to .jsonl file")
    parser.add_argument("--table", default=DEFAULT_TABLE, help="Target table name")
    args = parser.parse_args()

    conn = get_connection()
    try:
        ensure_table(conn, args.table)
        load_file(conn, args.file, args.table)
    finally:
        conn.close()


if __name__ == "__main__":
    main() 