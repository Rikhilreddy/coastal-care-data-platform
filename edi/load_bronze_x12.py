"""
Land inbound X12 files in bronze, exactly as received: one row per segment.   EDI-2

Bronze rule: store what arrived, parse later. Every segment of every file becomes a row in
bronze.x12_segment with its position and its elements as a text array (elements[1] is the
first element after the segment ID). Loops and claims are derived in dbt, where the logic is
versioned and tested.

For each file:
  1. Fingerprint (SHA-256); an identical file already loaded is skipped (idempotent).
  2. Read the delimiters from the ISA header (element separator = ISA position 4,
     component separator = ISA16, segment terminator = character after ISA16),
     so files from any trading partner parse correctly.
  3. One transaction: delete rows previously loaded from this file name, insert segments.
  4. Reconcile before commit: segments in file = rows in database; every ST/SE pair's SE01
     equals its segment count; Sum of CLM02 (claim charges) in file = Sum in database.
  5. Record the outcome in audit.load_manifest.

Run from the project root:
    python edi/load_bronze_x12.py                                  # default inbound folder
    python edi/load_bronze_x12.py --dir data/edi/outbound/837P     # round-trip test of our own files
"""
from __future__ import annotations

import argparse
import hashlib
import logging
import os
import sys
import uuid
from decimal import Decimal
from pathlib import Path

import psycopg2
import psycopg2.extras
from dotenv import load_dotenv

TARGET = "bronze.x12_segment"
AUDIT_DDL_PATH = Path("sql/01_create_audit_tables.sql")
DDL = f"""
CREATE SCHEMA IF NOT EXISTS bronze;
CREATE TABLE IF NOT EXISTS {TARGET} (
    segment_id     TEXT        NOT NULL,          -- ISA, ST, CLM, SV1, ...
    elements       TEXT[]      NOT NULL,          -- elements[1] = first element after the ID
    segment_num    INTEGER     NOT NULL,          -- position in the file (1 = ISA)
    raw_segment    TEXT        NOT NULL,          -- exactly as received
    component_sep  CHAR(1)     NOT NULL,          -- from ISA16
    _batch_id      UUID        NOT NULL,
    _source_file   TEXT        NOT NULL,
    _loaded_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_x12_segment_file ON {TARGET} (_source_file, segment_num);
CREATE INDEX IF NOT EXISTS ix_x12_segment_id   ON {TARGET} (segment_id);
"""

log = logging.getLogger("x12_loader")


def get_connection(autocommit=False):
    load_dotenv()
    conn = psycopg2.connect(
        host=os.getenv("PG_HOST", "localhost"), port=os.getenv("PG_PORT", "5432"),
        dbname=os.getenv("PG_DB", "coastal_care"),
        user=os.getenv("PG_USER") or None, password=os.getenv("PG_PASSWORD") or None)
    conn.autocommit = autocommit
    return conn


def parse_x12(text: str) -> tuple[list[tuple[str, list[str], str]], str]:
    """Split an interchange into segments using the delimiters declared in its ISA header."""
    text = text.lstrip()
    if not text.startswith("ISA") or len(text) < 106:
        raise ValueError("not an X12 interchange (missing ISA header)")
    elem_sep, comp_sep, seg_term = text[3], text[104], text[105]
    segments = []
    for raw in text.split(seg_term):
        raw = raw.strip("\r\n ")
        if not raw:
            continue
        parts = raw.split(elem_sep)
        segments.append((parts[0], parts[1:], raw))
    return segments, comp_sep


def check_envelopes(segments) -> None:
    ids = [s[0] for s in segments]
    if ids[0] != "ISA" or ids[-1] != "IEA":
        raise ValueError("interchange must start with ISA and end with IEA")
    st_pos = None
    for i, (seg_id, el, _) in enumerate(segments):
        if seg_id == "ST":
            st_pos = i
        elif seg_id == "SE":
            if st_pos is None:
                raise ValueError("SE without ST")
            if int(el[0]) != i - st_pos + 1:
                raise ValueError(f"SE01={el[0]} but transaction has {i - st_pos + 1} segments")
            st_pos = None


def already_loaded(cur, name, file_hash) -> bool:
    cur.execute("""SELECT 1 FROM audit.load_manifest WHERE source_file = %s AND file_sha256 = %s
                   AND target_table = %s AND status = 'SUCCESS' LIMIT 1""", (name, file_hash, TARGET))
    return cur.fetchone() is not None


def manifest(cur, batch_id, path, file_hash, status, message=None, src=None, loaded=None, amt=None, db_amt=None):
    cur.execute("""INSERT INTO audit.load_manifest (batch_id, source_system, source_file, file_sha256,
                       file_size_bytes, target_table, source_row_count, loaded_row_count, control_amount_columns,
                       source_control_amount, loaded_control_amount, status, message, finished_at)
                   VALUES (%s,'x12',%s,%s,%s,%s,%s,%s,'CLM02',%s,%s,%s,%s,now())""",
                (batch_id, path.name, file_hash, path.stat().st_size, TARGET, src, loaded, amt, db_amt, status, message))


def load_one(path: Path, data_conn, audit_cur, force: bool) -> str:
    raw = path.read_bytes()
    file_hash = hashlib.sha256(raw).hexdigest()
    batch_id = str(uuid.uuid4())
    if not force and already_loaded(audit_cur, path.name, file_hash):
        manifest(audit_cur, batch_id, path, file_hash, "SKIPPED", "Identical file already loaded successfully")
        return "SKIPPED"
    try:
        segments, comp_sep = parse_x12(raw.decode("ascii"))
        check_envelopes(segments)
        clm_total = sum((Decimal(el[1]) for sid, el, _ in segments if sid == "CLM"), Decimal("0"))
        rows = [(sid, el, n, rawseg, comp_sep, batch_id, path.name)
                for n, (sid, el, rawseg) in enumerate(segments, 1)]
        with data_conn:
            with data_conn.cursor() as cur:
                cur.execute(f"DELETE FROM {TARGET} WHERE _source_file = %s", (path.name,))
                psycopg2.extras.execute_values(
                    cur, f"INSERT INTO {TARGET} (segment_id, elements, segment_num, raw_segment, component_sep, "
                         f"_batch_id, _source_file) VALUES %s", rows, page_size=5000)
                cur.execute(f"""SELECT count(*), coalesce(sum((elements[2])::numeric) FILTER (WHERE segment_id = 'CLM'), 0)
                                FROM {TARGET} WHERE _batch_id = %s""", (batch_id,))
                db_rows, db_total = cur.fetchone()
                if db_rows != len(segments) or Decimal(db_total) != clm_total:
                    raise RuntimeError(f"reconciliation failed: file {len(segments)} segments / ${clm_total}, "
                                       f"database {db_rows} / ${db_total}")
    except Exception as exc:
        manifest(audit_cur, batch_id, path, file_hash, "FAILED", str(exc)[:1000])
        log.error("FAIL  %s: %s", path.name, exc)
        return "FAILED"
    manifest(audit_cur, batch_id, path, file_hash, "SUCCESS", "Segments, SE counts and CLM02 total reconciled",
             len(segments), db_rows, clm_total, Decimal(db_total))
    return "SUCCESS"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dir", default="data/edi/inbound", help="folder with .x12 files (searched recursively)")
    ap.add_argument("--force", action="store_true", help="reload unchanged files")
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s", datefmt="%H:%M:%S")

    files = sorted(Path(args.dir).rglob("*.x12"))
    if not files:
        log.error("No .x12 files under %s", args.dir)
        return 1
    audit_conn, data_conn = get_connection(autocommit=True), get_connection()
    results = {"SUCCESS": 0, "SKIPPED": 0, "FAILED": 0}
    try:
        with audit_conn.cursor() as audit_cur:
            audit_cur.execute(AUDIT_DDL_PATH.read_text())
            audit_cur.execute(DDL)
            for path in files:
                results[load_one(path, data_conn, audit_cur, args.force)] += 1
            audit_cur.execute(f"ANALYZE {TARGET}")
    finally:
        data_conn.close()
        audit_conn.close()
    print("\nSummary  " + "  ".join(f"{k} {v}" for k, v in results.items()))
    return 1 if results["FAILED"] else 0


if __name__ == "__main__":
    sys.exit(main())
