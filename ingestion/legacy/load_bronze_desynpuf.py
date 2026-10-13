"""
Load DE-SynPUF legacy source files into the bronze layer.

For each file listed in ingestion/legacy/desynpuf_sources.yaml:
  1. Fingerprint the file (SHA-256). If this exact file was already loaded
     successfully, skip it, so reruns never create duplicates.
  2. Stream the CSV into PostgreSQL with COPY. Every source value is stored as
     text, unchanged, plus audit columns: _batch_id, _source_file,
     _source_row_num, (_file_year), _loaded_at.
  3. Reconcile: row count and control dollar totals computed from the source
     file must equal what landed in the database. Any mismatch rolls back.
  4. Record the outcome in audit.load_manifest.

Run from the project root:
    python ingestion/legacy/load_bronze_desynpuf.py
    python ingestion/legacy/load_bronze_desynpuf.py --force   # reload unchanged files
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import logging
import os
import re
import sys
import uuid
from decimal import Decimal, InvalidOperation
from pathlib import Path

import psycopg2
import yaml
from dotenv import load_dotenv
from psycopg2 import sql

CONFIG_PATH = Path("ingestion/legacy/desynpuf_sources.yaml")
AUDIT_DDL_PATH = Path("sql/01_create_audit_tables.sql")
CHUNK_ROWS = 100_000
BASE_AUDIT_COLUMNS = ["_batch_id", "_source_file", "_source_row_num"]

log = logging.getLogger("bronze_loader")


# ---------------------------------------------------------------- helpers ---

def get_connection(autocommit: bool = False):
    load_dotenv()
    conn = psycopg2.connect(
        host=os.getenv("PG_HOST", "localhost"),
        port=os.getenv("PG_PORT", "5432"),
        dbname=os.getenv("PG_DB", "coastal_care"),
        user=os.getenv("PG_USER") or None,
        password=os.getenv("PG_PASSWORD") or None,
    )
    conn.autocommit = autocommit
    return conn


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_header(path: Path) -> list[str]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return [col.strip().lower() for col in next(csv.reader(handle))]


def to_decimal(value: str, column: str, row_num: int) -> Decimal:
    if value == "":
        return Decimal("0")
    try:
        return Decimal(value)
    except InvalidOperation as exc:
        raise ValueError(
            f"Non-numeric control amount {value!r} in column {column} at source row {row_num}"
        ) from exc


def table_ident(qualified: str) -> sql.Composed:
    schema, table = qualified.split(".")
    return sql.SQL("{}.{}").format(sql.Identifier(schema), sql.Identifier(table))


def audit_columns(with_file_year: bool) -> list[str]:
    return BASE_AUDIT_COLUMNS + (["_file_year"] if with_file_year else [])


# ------------------------------------------------------------- table DDL ---

def ensure_table(cur, target: str, source_cols: list[str], with_file_year: bool) -> None:
    """Create the bronze table, or verify an existing one still matches the file."""
    schema, table = target.split(".")
    cur.execute(
        """
        SELECT column_name FROM information_schema.columns
        WHERE table_schema = %s AND table_name = %s
        ORDER BY ordinal_position
        """,
        (schema, table),
    )
    existing = [row[0] for row in cur.fetchall()]
    expected = source_cols + audit_columns(with_file_year) + ["_loaded_at"]

    if existing:
        if existing != expected:
            raise RuntimeError(
                f"Schema drift on {target}: file columns no longer match the table. "
                f"Expected {expected}, found {existing}."
            )
        return

    col_defs = [sql.SQL("{} TEXT").format(sql.Identifier(c)) for c in source_cols]
    col_defs += [
        sql.SQL("_batch_id UUID NOT NULL"),
        sql.SQL("_source_file TEXT NOT NULL"),
        sql.SQL("_source_row_num BIGINT NOT NULL"),
    ]
    if with_file_year:
        col_defs.append(sql.SQL("_file_year INTEGER NOT NULL"))
    col_defs.append(sql.SQL("_loaded_at TIMESTAMPTZ NOT NULL DEFAULT now()"))

    cur.execute(sql.SQL("CREATE TABLE {} ({})").format(table_ident(target), sql.SQL(", ").join(col_defs)))
    cur.execute(sql.SQL("CREATE INDEX ON {} (_source_file)").format(table_ident(target)))
    cur.execute(sql.SQL("CREATE INDEX ON {} (_batch_id)").format(table_ident(target)))
    log.info("  created table %s (%d source columns)", target, len(source_cols))


# ------------------------------------------------------------------ COPY ---

def copy_file(cur, path: Path, target: str, header: list[str], batch_id: str,
              file_year: int | None, control_cols: list[str]) -> tuple[int, Decimal]:
    """Stream the CSV into the table in chunks. Returns (row_count, control_amount) from the source."""
    copy_cols = header + audit_columns(file_year is not None)
    copy_stmt = sql.SQL("COPY {} ({}) FROM STDIN WITH (FORMAT csv)").format(
        table_ident(target), sql.SQL(", ").join(map(sql.Identifier, copy_cols))
    ).as_string(cur)
    control_idx = [header.index(c) for c in control_cols]

    buffer = io.StringIO()
    writer = csv.writer(buffer)
    rows, amount = 0, Decimal("0")

    def flush() -> None:
        buffer.seek(0)
        cur.copy_expert(copy_stmt, buffer)
        buffer.seek(0)
        buffer.truncate(0)

    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.reader(handle)
        next(reader)  # header
        for row_num, row in enumerate(reader, start=1):
            if len(row) != len(header):
                raise ValueError(
                    f"Malformed row {row_num}: {len(row)} fields, expected {len(header)}"
                )
            for i in control_idx:
                amount += to_decimal(row[i], header[i], row_num)
            extras = [batch_id, path.name, row_num] + ([file_year] if file_year is not None else [])
            writer.writerow(row + extras)
            rows += 1
            if rows % CHUNK_ROWS == 0:
                flush()
                log.info("    %s rows copied", f"{rows:,}")
        if buffer.tell():
            flush()
    return rows, amount


def loaded_totals(cur, target: str, batch_id: str, control_cols: list[str]) -> tuple[int, Decimal]:
    if control_cols:
        amount_expr = sql.SQL(" + ").join(
            sql.SQL("COALESCE({}::numeric, 0)").format(sql.Identifier(c)) for c in control_cols
        )
    else:
        amount_expr = sql.SQL("0")
    cur.execute(
        sql.SQL("SELECT count(*), COALESCE(SUM({}), 0) FROM {} WHERE _batch_id = %s").format(
            amount_expr, table_ident(target)
        ),
        (batch_id,),
    )
    count, amount = cur.fetchone()
    return int(count), Decimal(amount)


# -------------------------------------------------------------- manifest ---

def already_loaded(audit_cur, file_name: str, file_hash: str, target: str) -> bool:
    audit_cur.execute(
        """
        SELECT 1 FROM audit.load_manifest
        WHERE source_file = %s AND file_sha256 = %s AND target_table = %s AND status = 'SUCCESS'
        LIMIT 1
        """,
        (file_name, file_hash, target),
    )
    return audit_cur.fetchone() is not None


def start_manifest(audit_cur, batch_id, system, path, file_hash, target, control_cols, status="RUNNING", message=None):
    audit_cur.execute(
        """
        INSERT INTO audit.load_manifest
            (batch_id, source_system, source_file, file_sha256, file_size_bytes,
             target_table, control_amount_columns, status, message, finished_at)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s,
                CASE WHEN %s = 'RUNNING' THEN NULL ELSE now() END)
        """,
        (batch_id, system, path.name, file_hash, path.stat().st_size, target,
         ",".join(control_cols), status, message, status),
    )


def finish_manifest(audit_cur, batch_id, status, message=None, src_rows=None,
                    loaded_rows=None, src_amount=None, loaded_amount=None):
    audit_cur.execute(
        """
        UPDATE audit.load_manifest
        SET status = %s, message = %s, source_row_count = %s, loaded_row_count = %s,
            source_control_amount = %s, loaded_control_amount = %s, finished_at = now()
        WHERE batch_id = %s
        """,
        (status, message, src_rows, loaded_rows, src_amount, loaded_amount, batch_id),
    )


# ------------------------------------------------------------------ main ---

def load_one(path: Path, entry: dict, system: str, force: bool, data_conn, audit_cur) -> str:
    target = entry["target_table"]
    control_cols = [c.lower() for c in entry.get("control_amount_columns", [])]
    file_hash = sha256_of(path)
    batch_id = str(uuid.uuid4())

    if not force and already_loaded(audit_cur, path.name, file_hash, target):
        start_manifest(audit_cur, batch_id, system, path, file_hash, target, control_cols,
                       status="SKIPPED", message="Identical file already loaded successfully")
        log.info("SKIP  %s (unchanged since last successful load)", path.name)
        return "SKIPPED"

    file_year = None
    if entry.get("file_year_regex"):
        match = re.search(entry["file_year_regex"], path.name)
        if not match:
            raise ValueError(f"file_year_regex did not match file name {path.name}")
        file_year = int(match.group(1))

    header = read_header(path)
    missing = [c for c in control_cols if c not in header]
    if missing:
        raise ValueError(f"Control amount columns {missing} not found in {path.name}")

    log.info("LOAD  %s -> %s", path.name, target)
    start_manifest(audit_cur, batch_id, system, path, file_hash, target, control_cols)
    try:
        with data_conn:  # one transaction: commits on success, rolls back on any error
            with data_conn.cursor() as cur:
                ensure_table(cur, target, header, file_year is not None)
                cur.execute(sql.SQL("DELETE FROM {} WHERE _source_file = %s").format(table_ident(target)),
                            (path.name,))
                if cur.rowcount:
                    log.info("  replaced %s previously loaded rows", f"{cur.rowcount:,}")
                src_rows, src_amount = copy_file(cur, path, target, header, batch_id, file_year, control_cols)
                db_rows, db_amount = loaded_totals(cur, target, batch_id, control_cols)
                if src_rows != db_rows or src_amount != db_amount:
                    raise RuntimeError(
                        f"Reconciliation failed: source {src_rows:,} rows / ${src_amount:,.2f}, "
                        f"loaded {db_rows:,} rows / ${db_amount:,.2f}"
                    )
    except Exception as exc:
        finish_manifest(audit_cur, batch_id, "FAILED", message=str(exc)[:1000])
        log.error("FAIL  %s: %s", path.name, exc)
        return "FAILED"

    finish_manifest(audit_cur, batch_id, "SUCCESS",
                    message="Row count and control amount reconciled",
                    src_rows=src_rows, loaded_rows=db_rows,
                    src_amount=src_amount, loaded_amount=db_amount)
    log.info("  OK  %s rows | control total $%s | reconciled", f"{db_rows:,}", f"{db_amount:,.2f}")
    return "SUCCESS"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--force", action="store_true", help="reload files even if unchanged")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s", datefmt="%H:%M:%S")

    config = yaml.safe_load(CONFIG_PATH.read_text())
    source_dir = Path(config["source_dir"])

    audit_conn = get_connection(autocommit=True)  # manifest writes survive data rollbacks
    data_conn = get_connection(autocommit=False)
    results: dict[str, str] = {}
    try:
        with audit_conn.cursor() as audit_cur:
            audit_cur.execute(AUDIT_DDL_PATH.read_text())
            for entry in config["files"]:
                paths = sorted(source_dir.glob(entry["pattern"]))
                if not paths:
                    log.error("FAIL  no files match %s in %s", entry["pattern"], source_dir)
                    results[entry["pattern"]] = "FAILED"
                    continue
                for path in paths:
                    results[path.name] = load_one(path, entry, config["source_system"],
                                                  args.force, data_conn, audit_cur)
    finally:
        data_conn.close()
        audit_conn.close()

    print("\nSummary")
    for name, status in results.items():
        print(f"  {status:<8} {name}")
    return 1 if "FAILED" in results.values() else 0


if __name__ == "__main__":
    sys.exit(main())
