"""
Land HL7 v2 messages in bronze exactly as received: one row per segment.   HL7-1

Separators come from each message's MSH (MSH-1 field separator, MSH-2 encoding characters),
so any sender parses. Fields are stored as a text array numbered like the HL7 standard:
fields[1] = SEG-1. For MSH, fields[1] is the field separator itself, so fields[9] = MSH-9
(message type) and fields[10] = MSH-10 (control ID), matching the spec.

Per file (one transaction): fingerprint/skip, delete prior rows for the file, insert,
reconcile messages and segments file vs database, and require MSH, EVN, PID, PV1 in every
message. Outcome recorded in audit.load_manifest.

Run:  python hl7/load_bronze_hl7.py --dir data/hl7/outbound/adt
"""
from __future__ import annotations

import argparse
import hashlib
import logging
import os
import sys
import uuid
from pathlib import Path

import psycopg2
import psycopg2.extras
from dotenv import load_dotenv

TARGET = "bronze.hl7_segment"
AUDIT_DDL_PATH = Path("sql/01_create_audit_tables.sql")
REQUIRED = {"MSH", "EVN", "PID", "PV1"}
DDL = f"""
CREATE SCHEMA IF NOT EXISTS bronze;
CREATE TABLE IF NOT EXISTS {TARGET} (
    message_control_id TEXT    NOT NULL,      -- MSH-10
    message_type       TEXT    NOT NULL,      -- MSH-9, e.g. ADT^A01^ADT_A01
    message_num        INTEGER NOT NULL,      -- position of the message in the file
    segment_num        INTEGER NOT NULL,      -- position of the segment in the message
    segment_id         TEXT    NOT NULL,
    fields             TEXT[]  NOT NULL,      -- fields[n] = SEG-n (MSH: fields[1] = '|')
    raw_segment        TEXT    NOT NULL,
    component_sep      CHAR(1) NOT NULL,
    repetition_sep     CHAR(1) NOT NULL,
    _batch_id          UUID    NOT NULL,
    _source_file       TEXT    NOT NULL,
    _loaded_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_hl7_segment_msg ON {TARGET} (message_control_id);
CREATE INDEX IF NOT EXISTS ix_hl7_segment_file ON {TARGET} (_source_file);
"""
log = logging.getLogger("hl7_loader")


def get_connection(autocommit=False):
    load_dotenv()
    conn = psycopg2.connect(host=os.getenv("PG_HOST", "localhost"), port=os.getenv("PG_PORT", "5432"),
                            dbname=os.getenv("PG_DB", "coastal_care"),
                            user=os.getenv("PG_USER") or None, password=os.getenv("PG_PASSWORD") or None)
    conn.autocommit = autocommit
    return conn


def parse_messages(text: str):
    """Yield (message_segments, separators) for each message; segments end with \\r."""
    lines = [s for s in text.replace("\n", "\r").split("\r") if s.strip()]
    msg = []
    for seg in lines:
        if seg.startswith("MSH") and msg:
            yield msg
            msg = []
        msg.append(seg)
    if msg:
        yield msg


def split_segment(seg: str, field_sep: str) -> tuple[str, list[str]]:
    parts = seg.split(field_sep)
    if parts[0] == "MSH":
        return "MSH", [field_sep] + parts[1:]       # MSH-1 is the separator itself
    return parts[0], parts[1:]


def load_one(path: Path, data_conn, audit_cur, force: bool) -> str:
    raw = path.read_bytes()
    file_hash = hashlib.sha256(raw).hexdigest()
    batch_id = str(uuid.uuid4())
    audit_cur.execute("""SELECT 1 FROM audit.load_manifest WHERE source_file=%s AND file_sha256=%s
                         AND target_table=%s AND status='SUCCESS' LIMIT 1""", (path.name, file_hash, TARGET))
    if not force and audit_cur.fetchone():
        status, msg_count, rows = "SKIPPED", None, None
    else:
        try:
            rows, msg_count = [], 0
            for m_num, msg in enumerate(parse_messages(raw.decode("ascii", errors="replace")), 1):
                if not msg[0].startswith("MSH"):
                    raise ValueError(f"message {m_num} does not start with MSH")
                field_sep, enc = msg[0][3], msg[0][4:8]
                comp, rep = enc[0], enc[1]
                parsed = [split_segment(s, field_sep) for s in msg]
                ids = {p[0] for p in parsed}
                if not REQUIRED <= ids:
                    raise ValueError(f"message {m_num} missing segments {sorted(REQUIRED - ids)}")
                msh = parsed[0][1]
                ctrl, mtype = msh[9], msh[8]
                for s_num, (seg_id, fields) in enumerate(parsed, 1):
                    rows.append((ctrl, mtype, m_num, s_num, seg_id, fields, msg[s_num - 1], comp, rep,
                                 batch_id, path.name))
                msg_count += 1
            with data_conn:
                with data_conn.cursor() as cur:
                    cur.execute(f"DELETE FROM {TARGET} WHERE _source_file = %s", (path.name,))
                    psycopg2.extras.execute_values(cur, f"""INSERT INTO {TARGET} (message_control_id, message_type,
                        message_num, segment_num, segment_id, fields, raw_segment, component_sep, repetition_sep,
                        _batch_id, _source_file) VALUES %s""", rows, page_size=5000)
                    cur.execute(f"SELECT count(*), count(DISTINCT message_num) FROM {TARGET} WHERE _batch_id=%s",
                                (batch_id,))
                    db_rows, db_msgs = cur.fetchone()
                    if db_rows != len(rows) or db_msgs != msg_count:
                        raise RuntimeError(f"reconciliation failed: file {msg_count} msgs/{len(rows)} segs, "
                                           f"db {db_msgs}/{db_rows}")
            status = "SUCCESS"
        except Exception as exc:
            log.error("FAIL  %s: %s", path.name, exc)
            status, msg_count, rows = "FAILED", None, None
            audit_cur.execute("""INSERT INTO audit.load_manifest (batch_id, source_system, source_file, file_sha256,
                file_size_bytes, target_table, status, message, finished_at) VALUES (%s,'hl7',%s,%s,%s,%s,'FAILED',%s,now())""",
                (batch_id, path.name, file_hash, path.stat().st_size, TARGET, str(exc)[:1000]))
            return status
    audit_cur.execute("""INSERT INTO audit.load_manifest (batch_id, source_system, source_file, file_sha256,
        file_size_bytes, target_table, source_row_count, loaded_row_count, status, message, finished_at)
        VALUES (%s,'hl7',%s,%s,%s,%s,%s,%s,%s,%s,now())""",
        (batch_id, path.name, file_hash, path.stat().st_size, TARGET, msg_count, len(rows) if rows else None,
         status, "messages and segments reconciled" if status == "SUCCESS" else "Identical file already loaded"))
    return status


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dir", default="data/hl7/inbound")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s", datefmt="%H:%M:%S")
    files = sorted(Path(args.dir).rglob("*.hl7"))
    if not files:
        log.error("No .hl7 files under %s", args.dir)
        return 1
    audit_conn, data_conn = get_connection(autocommit=True), get_connection()
    results = {"SUCCESS": 0, "SKIPPED": 0, "FAILED": 0}
    try:
        with audit_conn.cursor() as cur:
            cur.execute(AUDIT_DDL_PATH.read_text())
            cur.execute(DDL)
            for p in files:
                results[load_one(p, data_conn, cur, args.force)] += 1
    finally:
        data_conn.close(); audit_conn.close()
    print("\nSummary  " + "  ".join(f"{k} {v}" for k, v in results.items()))
    return 1 if results["FAILED"] else 0


if __name__ == "__main__":
    sys.exit(main())
