"""
Load healthcare code sets into the ref schema.

Tables loaded (full refresh each time a source file changes):
  ref.icd10cm            <- ICD-10-CM FY2027 order file (fixed width)
  ref.gem_icd9_to_icd10  <- CMS 2018 diagnosis GEM, forward
  ref.gem_icd10_to_icd9  <- CMS 2018 diagnosis GEM, backward
  ref.hcpcs              <- HCPCS Level II quarterly file (Excel version, named columns)
  ref.icd9cm             <- ICD-9-CM v32 long diagnosis descriptions
  ref.icd9_dx_override   <- SME-reviewed conversion overrides (dbt/seeds/icd9_dx_overrides.csv)

Each load: fingerprint the file (skip if unchanged), parse, replace the table in
one transaction, reconcile parsed rows vs loaded rows, record in audit.load_manifest.

Run from the project root:
    python ingestion/reference/load_reference.py
    python ingestion/reference/load_reference.py --force
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
from pathlib import Path
from typing import Callable

import pandas as pd
import psycopg2
from dotenv import load_dotenv
from psycopg2 import sql

DDL_FILES = [Path("sql/01_create_audit_tables.sql"), Path("sql/02_create_ref_tables.sql")]
SOURCE_SYSTEM = "REFERENCE"

log = logging.getLogger("reference_loader")


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


def read_lines(path: Path) -> list[str]:
    """Read a text file, tolerating the occasional non-UTF-8 character in CMS files."""
    raw = path.read_bytes()
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        text = raw.decode("latin-1")
    return [line.rstrip("\r\n") for line in text.splitlines() if line.strip()]


def flag_parts(flags: str) -> tuple[bool, bool, bool, int, int]:
    if not re.fullmatch(r"[01][01][01]\d\d", flags):
        raise ValueError(f"Unexpected GEM flag string {flags!r}")
    return flags[0] == "1", flags[1] == "1", flags[2] == "1", int(flags[3]), int(flags[4])


# ---------------------------------------------------------------- parsers ---

def parse_icd10cm(path: Path) -> tuple[list[str], list[list]]:
    """Fixed width: order(1-5) code(7-13) billable(15) short(17-76) long(78+)."""
    rows = []
    for n, line in enumerate(read_lines(path), start=1):
        billable = line[14:15]
        if billable not in ("0", "1"):
            raise ValueError(f"Line {n}: billable flag {billable!r} is not 0/1")
        rows.append([int(line[0:5]), line[6:13].strip(), billable == "1",
                     line[16:76].strip(), line[77:].strip(), "FY2027"])
    cols = ["order_number", "icd10_code", "is_billable", "short_desc", "long_desc", "code_set_version"]
    return cols, rows


def make_gem_parser(source_col: str, target_col: str) -> Callable[[Path], tuple[list[str], list[list]]]:
    """GEM files are whitespace separated: source, target, 5-character flags."""
    def parse(path: Path) -> tuple[list[str], list[list]]:
        rows = []
        for n, line in enumerate(read_lines(path), start=1):
            parts = line.split()
            if len(parts) != 3:
                raise ValueError(f"Line {n}: expected 3 fields, found {len(parts)}: {line!r}")
            source, target, flags = parts
            approximate, no_map, combination, scenario, choice = flag_parts(flags)
            rows.append([source, None if target == "NoDx" else target, flags,
                         approximate, no_map, combination, scenario, choice])
        cols = [source_col, target_col, "flags", "approximate", "no_map",
                "combination", "scenario", "choice_list"]
        return cols, rows
    return parse


HCPCS_COLUMN_ALIASES = {
    "code":  ["HCPC", "HCPCS", "HCPCS CODE"],
    "seq":   ["SEQNUM", "SEQ NUM", "SEQUENCE NUMBER"],
    "recid": ["RECID", "REC ID", "RECORD ID"],
    "long":  ["LONG DESCRIPTION", "LONG DESC"],
    "short": ["SHORT DESCRIPTION", "SHORT DESC"],
    "add":   ["ADD DT", "ADD DATE"],
    "eff":   ["ACT EFF DT", "ACTION EFFECTIVE DATE"],
    "term":  ["TERM DT", "TERMINATION DATE"],
}


def to_date(value):
    if value is None or (isinstance(value, float) and pd.isna(value)) or str(value).strip() in ("", "nan", "NaT"):
        return None
    text = str(value).strip()
    if re.fullmatch(r"\d{8}", text):
        parsed = pd.to_datetime(text, format="%Y%m%d", errors="coerce")
    else:
        parsed = pd.to_datetime(text, errors="coerce")
    return None if pd.isna(parsed) else parsed.date()


def parse_hcpcs(path: Path) -> tuple[list[str], list[list]]:
    df = pd.read_excel(path, dtype=str)
    normalized = {re.sub(r"\s+", " ", str(c)).strip().upper(): c for c in df.columns}
    found = {}
    for key, aliases in HCPCS_COLUMN_ALIASES.items():
        match = next((normalized[a] for a in aliases if a in normalized), None)
        if match is None and key in ("code", "long", "short"):
            raise ValueError(f"HCPCS file is missing a '{key}' column. Columns found: {list(df.columns)}")
        found[key] = match

    df = df[df[found["code"]].notna()].copy()
    df["_code"] = df[found["code"]].str.strip().str.upper()
    df = df[df["_code"].str.fullmatch(r"[A-Z0-9]{5}")]          # drops 2-character modifier rows
    if found["recid"]:
        df = df[df[found["recid"]].str.strip().isin(["3", "4"])]  # 3 = first line, 4 = continuation
    if found["seq"]:
        df = df.sort_values(["_code", found["seq"]])

    rows = []
    for code, group in df.groupby("_code", sort=True):
        first = group.iloc[0]
        long_desc = " ".join(s.strip() for s in group[found["long"]].dropna() if s.strip())
        rows.append([
            code,
            (first[found["short"]] or "").strip() if pd.notna(first[found["short"]]) else None,
            long_desc or None,
            to_date(first[found["add"]]) if found["add"] else None,
            to_date(first[found["eff"]]) if found["eff"] else None,
            to_date(first[found["term"]]) if found["term"] else None,
            "2026-Q4",
        ])
    cols = ["hcpcs_code", "short_desc", "long_desc", "add_date",
            "action_effective_date", "termination_date", "code_set_version"]
    return cols, rows


ICD9_LINE_RE = re.compile(r"^(\d{3,5}|V\d{2,4}|E\d{3,4})\s+(.+)$")


def parse_icd9cm(path: Path) -> tuple[list[str], list[list]]:
    """Each line: an ICD-9-CM code, whitespace, its long description."""
    rows = []
    for n, line in enumerate(read_lines(path), start=1):
        match = ICD9_LINE_RE.match(line.strip())
        if not match:
            raise ValueError(f"Line {n}: expected '<ICD-9 code> <description>', found {line[:60]!r}")
        rows.append([match.group(1), match.group(2).strip(), "v32"])
    return ["icd9_code", "long_desc", "code_set_version"], rows


OVERRIDE_COLUMNS = ["icd9_code", "icd10_code", "review_status", "rationale", "reviewed_by", "review_date"]
OVERRIDE_STATUSES = {"PROPOSED", "APPROVED", "REJECTED"}


def parse_overrides(path: Path) -> tuple[list[str], list[list]]:
    """SME override file. Every row needs a status; only APPROVED rows change conversions."""
    rows = []
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        missing = [c for c in OVERRIDE_COLUMNS if c not in (reader.fieldnames or [])]
        if missing:
            raise ValueError(f"Override file is missing columns {missing}")
        for n, rec in enumerate(reader, start=2):
            status = rec["review_status"].strip().upper()
            if status not in OVERRIDE_STATUSES:
                raise ValueError(f"Line {n}: review_status {status!r} must be one of {sorted(OVERRIDE_STATUSES)}")
            if status == "APPROVED" and not (rec["reviewed_by"].strip() and rec["review_date"].strip()):
                raise ValueError(f"Line {n}: APPROVED rows need reviewed_by and review_date")
            rows.append([rec["icd9_code"].strip(), rec["icd10_code"].strip().upper(), status,
                         rec["rationale"].strip(), rec["reviewed_by"].strip() or None,
                         to_date(rec["review_date"])])
    return OVERRIDE_COLUMNS, rows


# Paths are relative to the project root; a glob pattern must match exactly one file.
SOURCES = [
    ("data/reference/icd10cm_2027/icd10cm_order_2027.txt",             "ref.icd10cm",           parse_icd10cm),
    ("data/reference/gems_2018/2018_I9gem.txt",                        "ref.gem_icd9_to_icd10", make_gem_parser("icd9_code", "icd10_code")),
    ("data/reference/gems_2018/2018_I10gem.txt",                       "ref.gem_icd10_to_icd9", make_gem_parser("icd10_code", "icd9_code")),
    ("data/reference/hcpcs_2026_oct/HCPC2026_OCT_ANWEB_09232026.xlsx", "ref.hcpcs",             parse_hcpcs),
    ("data/reference/icd9cm_v32/*LONG*DX*.txt",                        "ref.icd9cm",            parse_icd9cm),
    ("dbt/seeds/icd9_dx_overrides.csv",                                "ref.icd9_dx_override",  parse_overrides),
]


# ------------------------------------------------------------------ load ---

def table_ident(qualified: str) -> sql.Composed:
    schema, table = qualified.split(".")
    return sql.SQL("{}.{}").format(sql.Identifier(schema), sql.Identifier(table))


def copy_rows(cur, target: str, cols: list[str], rows: list[list]) -> None:
    buffer = io.StringIO()
    writer = csv.writer(buffer)
    for row in rows:
        writer.writerow(["" if v is None else v for v in row])
    buffer.seek(0)
    stmt = sql.SQL("COPY {} ({}) FROM STDIN WITH (FORMAT csv)").format(
        table_ident(target), sql.SQL(", ").join(map(sql.Identifier, cols))
    ).as_string(cur)
    cur.copy_expert(stmt, buffer)


def load_one(pattern: str, target: str, parser, force: bool, data_conn, audit_cur) -> str:
    matches = sorted(Path(".").glob(pattern))
    if len(matches) != 1:
        log.error("FAIL  %s matched %d files (expected exactly 1): %s",
                  pattern, len(matches), [m.name for m in matches])
        return "FAILED"
    path = matches[0]
    file_hash, batch_id = sha256_of(path), str(uuid.uuid4())

    audit_cur.execute(
        """SELECT 1 FROM audit.load_manifest WHERE source_file = %s AND file_sha256 = %s
           AND target_table = %s AND status = 'SUCCESS' LIMIT 1""",
        (path.name, file_hash, target),
    )
    already = audit_cur.fetchone() is not None
    status = "SKIPPED" if (already and not force) else "RUNNING"
    audit_cur.execute(
        """INSERT INTO audit.load_manifest (batch_id, source_system, source_file, file_sha256,
               file_size_bytes, target_table, status, message, finished_at)
           VALUES (%s, %s, %s, %s, %s, %s, %s, %s, CASE WHEN %s = 'SKIPPED' THEN now() END)""",
        (batch_id, SOURCE_SYSTEM, path.name, file_hash, path.stat().st_size, target, status,
         "Identical file already loaded successfully" if status == "SKIPPED" else None, status),
    )
    if status == "SKIPPED":
        log.info("SKIP  %s (unchanged)", path.name)
        return "SKIPPED"

    log.info("LOAD  %s -> %s", path.name, target)
    try:
        cols, rows = parser(path)
        with data_conn:
            with data_conn.cursor() as cur:
                cur.execute(sql.SQL("TRUNCATE {}").format(table_ident(target)))
                copy_rows(cur, target, cols, rows)
                cur.execute(sql.SQL("SELECT count(*) FROM {}").format(table_ident(target)))
                loaded = cur.fetchone()[0]
                if loaded != len(rows):
                    raise RuntimeError(f"Reconciliation failed: parsed {len(rows):,}, loaded {loaded:,}")
    except Exception as exc:
        audit_cur.execute(
            "UPDATE audit.load_manifest SET status='FAILED', message=%s, finished_at=now() WHERE batch_id=%s",
            (str(exc)[:1000], batch_id),
        )
        log.error("FAIL  %s: %s", path.name, exc)
        return "FAILED"

    audit_cur.execute(
        """UPDATE audit.load_manifest SET status='SUCCESS', message='Row count reconciled',
               source_row_count=%s, loaded_row_count=%s, finished_at=now() WHERE batch_id=%s""",
        (len(rows), loaded, batch_id),
    )
    log.info("  OK  %s rows | reconciled", f"{loaded:,}")
    return "SUCCESS"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--force", action="store_true", help="reload files even if unchanged")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s", datefmt="%H:%M:%S")

    audit_conn = get_connection(autocommit=True)
    data_conn = get_connection(autocommit=False)
    results = {}
    try:
        with audit_conn.cursor() as audit_cur:
            for ddl in DDL_FILES:
                audit_cur.execute(ddl.read_text())
            for rel_path, target, parse in SOURCES:
                results[rel_path] = load_one(rel_path, target, parse, args.force, data_conn, audit_cur)
    finally:
        data_conn.close()
        audit_conn.close()

    print("\nSummary")
    for name, status in results.items():
        print(f"  {status:<8} {name}")
    return 1 if "FAILED" in results.values() else 0


if __name__ == "__main__":
    sys.exit(main())
