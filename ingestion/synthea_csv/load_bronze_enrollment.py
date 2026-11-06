"""
Land Synthea enrollment history in bronze, exactly as exported: EDI-4 source.

The 834 benefit enrollment files are generated FROM this history (as a payer's enrollment
system would), so the round trip can be proven: history in bronze = enrollment received.

  payers.csv            -> bronze.synthea_payers             (Id, NAME, OWNERSHIP)
  payer_transitions.csv -> bronze.synthea_payer_transitions  (one row per coverage span)

Same rules as every bronze loader: SHA-256 fingerprint (an unchanged file is skipped),
one transaction per file (delete this file's rows, insert, reconcile rows file = database
before commit), outcome in audit.load_manifest. OWNER_NAME is a person's name: bronze is
restricted (PHI); it is never carried past bronze.

Run from the project root:
    python ingestion/synthea_csv/load_bronze_enrollment.py
    python ingestion/synthea_csv/load_bronze_enrollment.py --dir data/source/synthea/csv --force
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import logging
import os
import sys
import uuid
from pathlib import Path

import psycopg2
import psycopg2.extras
from dotenv import load_dotenv

AUDIT_DDL_PATH = Path("sql/01_create_audit_tables.sql")
FILES = {
    "payers.csv": ("bronze.synthea_payers", ["Id", "NAME", "OWNERSHIP"]),
    "payer_transitions.csv": ("bronze.synthea_payer_transitions",
                              ["PATIENT", "MEMBERID", "START_DATE", "END_DATE", "PAYER", "SECONDARY_PAYER",
                               "PLAN_OWNERSHIP", "OWNER_NAME"]),
}
log = logging.getLogger("enrollment_loader")


def ddl(table: str, cols: list[str]) -> str:
    col_sql = ",\n    ".join(f"{c.lower()} TEXT" for c in cols)
    return f"""CREATE SCHEMA IF NOT EXISTS bronze;
CREATE TABLE IF NOT EXISTS {table} (
    {col_sql},
    _source_row_num INTEGER NOT NULL,
    _batch_id       UUID    NOT NULL,
    _source_file    TEXT    NOT NULL,
    _loaded_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);"""


def get_connection(autocommit=False):
    load_dotenv()
    conn = psycopg2.connect(host=os.getenv("PG_HOST", "localhost"), port=os.getenv("PG_PORT", "5432"),
                            dbname=os.getenv("PG_DB", "coastal_care"),
                            user=os.getenv("PG_USER") or None, password=os.getenv("PG_PASSWORD") or None)
    conn.autocommit = autocommit
    return conn


def manifest(cur, batch_id, path, file_hash, table, status, message, src=None, loaded=None):
    cur.execute("""INSERT INTO audit.load_manifest (batch_id, source_system, source_file, file_sha256, file_size_bytes,
                   target_table, source_row_count, loaded_row_count, status, message, finished_at)
                   VALUES (%s,'synthea_csv',%s,%s,%s,%s,%s,%s,%s,%s,now())""",
                (batch_id, path.name, file_hash, path.stat().st_size, table, src, loaded, status, message))


def load_one(path: Path, table: str, cols: list[str], data_conn, audit_cur, force: bool) -> str:
    raw = path.read_bytes()
    file_hash = hashlib.sha256(raw).hexdigest()
    batch_id = str(uuid.uuid4())
    audit_cur.execute("""SELECT 1 FROM audit.load_manifest WHERE source_file=%s AND file_sha256=%s
                         AND target_table=%s AND status='SUCCESS' LIMIT 1""", (path.name, file_hash, table))
    if not force and audit_cur.fetchone():
        manifest(audit_cur, batch_id, path, file_hash, table, "SKIPPED", "Identical file already loaded")
        return "SKIPPED"
    try:
        reader = csv.DictReader(io.StringIO(raw.decode("utf-8-sig")))
        missing = [c for c in cols if c not in (reader.fieldnames or [])]
        if missing:
            raise ValueError(f"missing columns {missing}")
        rows = [tuple(r[c] or None for c in cols) + (n, batch_id, path.name) for n, r in enumerate(reader, 2)]
        with data_conn, data_conn.cursor() as cur:
            cur.execute(f"DELETE FROM {table} WHERE _source_file = %s", (path.name,))
            psycopg2.extras.execute_values(
                cur, f"INSERT INTO {table} ({', '.join(c.lower() for c in cols)}, _source_row_num, _batch_id, _source_file) VALUES %s",
                rows, page_size=5000)
            cur.execute(f"SELECT count(*) FROM {table} WHERE _batch_id = %s", (batch_id,))
            db_rows = cur.fetchone()[0]
            if db_rows != len(rows):
                raise RuntimeError(f"reconciliation failed: file {len(rows)} rows, database {db_rows}")
    except Exception as exc:
        manifest(audit_cur, batch_id, path, file_hash, table, "FAILED", str(exc)[:1000])
        log.error("FAIL  %s: %s", path.name, exc)
        return "FAILED"
    manifest(audit_cur, batch_id, path, file_hash, table, "SUCCESS", "Rows reconciled", len(rows), db_rows)
    log.info("OK    %s -> %s (%s rows)", path.name, table, f"{db_rows:,}")
    return "SUCCESS"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dir", default="data/source/synthea/csv")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s", datefmt="%H:%M:%S")
    audit_conn, data_conn = get_connection(autocommit=True), get_connection()
    results = {"SUCCESS": 0, "SKIPPED": 0, "FAILED": 0}
    try:
        with audit_conn.cursor() as cur:
            cur.execute(AUDIT_DDL_PATH.read_text())
            for name, (table, cols) in FILES.items():
                cur.execute(ddl(table, cols))
                path = Path(args.dir) / name
                if not path.exists():
                    log.error("missing %s", path)
                    results["FAILED"] += 1
                    continue
                results[load_one(path, table, cols, data_conn, cur, args.force)] += 1
    finally:
        data_conn.close(); audit_conn.close()
    print("\nSummary  " + "  ".join(f"{k} {v}" for k, v in results.items()))
    return 1 if results["FAILED"] else 0


if __name__ == "__main__":
    sys.exit(main())
