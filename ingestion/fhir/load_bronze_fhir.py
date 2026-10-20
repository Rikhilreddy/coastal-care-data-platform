"""
Load Synthea FHIR R4 bundles into bronze.fhir_resource (FHIR-1).

One row per FHIR resource, stored unchanged as JSONB. For each bundle file:
  1. Fingerprint the file (SHA-256). An identical file already loaded successfully is
     skipped, so reruns never create duplicates.
  2. Parse the bundle. Keep resources whose type is in load_resource_types
     (ingestion/fhir/fhir_sources.yaml); count the rest by type.
  3. In ONE transaction: delete rows previously loaded from this file name (a bundle is a
     full snapshot of the patient, so a changed file replaces its old rows), then COPY.
  4. Reconcile before committing:
       bundle entries = loaded + skipped
       loaded resources (from file) = rows in the database for this batch
       sum of Claim.total.value (from file) = same sum computed in the database from JSONB
     Any mismatch rolls the file back.
  5. Record the outcome in audit.load_manifest (one row per file attempt).

A bad file fails alone: the others still load, and the run exits non-zero.

Run from the project root:
    python ingestion/fhir/load_bronze_fhir.py
    python ingestion/fhir/load_bronze_fhir.py --force    # reload unchanged files
    python ingestion/fhir/load_bronze_fhir.py --limit 20 # first 20 files (smoke test)
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import logging
import os
import sys
import time
import uuid
from collections import Counter
from decimal import Decimal
from pathlib import Path

import psycopg2
import yaml
from dotenv import load_dotenv

CONFIG_PATH = Path("ingestion/fhir/fhir_sources.yaml")
AUDIT_DDL_PATH = Path("sql/01_create_audit_tables.sql")
TARGET = "bronze.fhir_resource"

DDL = f"""
CREATE TABLE IF NOT EXISTS {TARGET} (
    resource_type     TEXT        NOT NULL,
    resource_id       TEXT,
    full_url          TEXT,                 -- bundle entry fullUrl (urn:uuid:...), used by references
    resource          JSONB       NOT NULL, -- the FHIR resource exactly as received
    _batch_id         UUID        NOT NULL,
    _source_file      TEXT        NOT NULL,
    _source_entry_num INTEGER     NOT NULL, -- position in bundle.entry (1-based), lineage
    _loaded_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_fhir_resource_type ON {TARGET} (resource_type);
CREATE INDEX IF NOT EXISTS ix_fhir_resource_file ON {TARGET} (_source_file);
CREATE INDEX IF NOT EXISTS ix_fhir_resource_batch ON {TARGET} (_batch_id);
"""

log = logging.getLogger("fhir_loader")


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


def claim_total(resource: dict) -> Decimal:
    value = (resource.get("total") or {}).get("value")
    return Decimal(str(value)) if value is not None else Decimal("0")


def already_loaded(cur, name: str, file_hash: str) -> bool:
    cur.execute(
        """SELECT 1 FROM audit.load_manifest
           WHERE source_file = %s AND file_sha256 = %s AND target_table = %s AND status = 'SUCCESS'
           LIMIT 1""",
        (name, file_hash, TARGET),
    )
    return cur.fetchone() is not None


def manifest(cur, batch_id, system, path, file_hash, control, status, message=None,
             src=None, loaded=None, src_amt=None, db_amt=None):
    cur.execute(
        """INSERT INTO audit.load_manifest
               (batch_id, source_system, source_file, file_sha256, file_size_bytes, target_table,
                source_row_count, loaded_row_count, control_amount_columns,
                source_control_amount, loaded_control_amount, status, message, finished_at)
           VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s, now())""",
        (batch_id, system, path.name, file_hash, path.stat().st_size, TARGET, src, loaded,
         control, src_amt, db_amt, status, message),
    )


def load_one(path: Path, cfg: dict, keep: set[str], force: bool, data_conn, audit_cur,
             skipped_totals: Counter) -> str:
    system, control = cfg["source_system"], cfg["control_amount"]
    file_hash = sha256_of(path)
    batch_id = str(uuid.uuid4())

    if not force and already_loaded(audit_cur, path.name, file_hash):
        manifest(audit_cur, batch_id, system, path, file_hash, control, "SKIPPED",
                 "Identical file already loaded successfully")
        return "SKIPPED"

    try:
        bundle = json.loads(path.read_text(encoding="utf-8"))
        if bundle.get("resourceType") != "Bundle":
            raise ValueError(f"not a FHIR Bundle (resourceType={bundle.get('resourceType')!r})")
        entries = bundle.get("entry", [])

        buf = io.StringIO()
        writer = csv.writer(buf)
        loaded, skipped = 0, Counter()
        src_amount = Decimal("0")
        for num, entry in enumerate(entries, 1):
            res = entry.get("resource") or {}
            rtype = res.get("resourceType", "(missing)")
            if rtype not in keep:
                skipped[rtype] += 1
                continue
            if rtype == "Claim":
                src_amount += claim_total(res)
            writer.writerow([rtype, res.get("id"), entry.get("fullUrl"),
                             json.dumps(res, ensure_ascii=False, separators=(",", ":")),
                             batch_id, path.name, num])
            loaded += 1
        if loaded + sum(skipped.values()) != len(entries):
            raise RuntimeError("entry accounting failed: loaded + skipped != bundle entries")

        with data_conn:                      # one transaction per file
            with data_conn.cursor() as cur:
                cur.execute(f"DELETE FROM {TARGET} WHERE _source_file = %s", (path.name,))
                replaced = cur.rowcount
                buf.seek(0)
                cur.copy_expert(
                    f"COPY {TARGET} (resource_type, resource_id, full_url, resource, "
                    f"_batch_id, _source_file, _source_entry_num) FROM STDIN WITH (FORMAT csv)",
                    buf,
                )
                cur.execute(
                    f"""SELECT count(*),
                               COALESCE(SUM((resource->'total'->>'value')::numeric)
                                        FILTER (WHERE resource_type = 'Claim'), 0)
                        FROM {TARGET} WHERE _batch_id = %s""",
                    (batch_id,),
                )
                db_rows, db_amount = cur.fetchone()
                if db_rows != loaded or Decimal(db_amount) != src_amount:
                    raise RuntimeError(
                        f"reconciliation failed: file {loaded:,} resources / ${src_amount:,.2f}, "
                        f"database {db_rows:,} / ${Decimal(db_amount):,.2f}"
                    )
    except Exception as exc:
        manifest(audit_cur, batch_id, system, path, file_hash, control, "FAILED", str(exc)[:1000])
        log.error("FAIL  %s: %s", path.name, exc)
        return "FAILED"

    skipped_totals.update(skipped)
    note = {"replaced_rows": replaced, "skipped": dict(sorted(skipped.items()))}
    manifest(audit_cur, batch_id, system, path, file_hash, control, "SUCCESS",
             json.dumps(note), len(entries), loaded, src_amount, Decimal(db_amount))
    return "SUCCESS"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--force", action="store_true", help="reload files even if unchanged")
    parser.add_argument("--limit", type=int, help="load only the first N files (smoke test)")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s", datefmt="%H:%M:%S")

    cfg = yaml.safe_load(CONFIG_PATH.read_text())
    keep = set(cfg["load_resource_types"])
    files = sorted(Path(cfg["source_dir"]).glob(cfg["file_pattern"]))[: args.limit]
    if not files:
        log.error("No files match %s in %s", cfg["file_pattern"], cfg["source_dir"])
        return 1

    audit_conn = get_connection(autocommit=True)   # manifest rows survive data rollbacks
    data_conn = get_connection(autocommit=False)
    results, skipped_totals = Counter(), Counter()
    started = time.time()
    try:
        with audit_conn.cursor() as audit_cur:
            audit_cur.execute(AUDIT_DDL_PATH.read_text())
            audit_cur.execute(DDL)
            for n, path in enumerate(files, 1):
                results[load_one(path, cfg, keep, args.force, data_conn, audit_cur, skipped_totals)] += 1
                if n % 100 == 0 or n == len(files):
                    log.info("  %d/%d files | %s | %.0fs", n, len(files),
                             ", ".join(f"{k} {v}" for k, v in sorted(results.items())),
                             time.time() - started)
            audit_cur.execute(f"ANALYZE {TARGET}")
    finally:
        data_conn.close()
        audit_conn.close()

    print("\nSummary")
    for status, count in sorted(results.items()):
        print(f"  {status:<8} {count:,} files")
    if skipped_totals:
        print("  Skipped by design (counted, not stored):")
        for rtype, count in skipped_totals.most_common():
            print(f"    {rtype:<26} {count:,}")
    return 1 if results["FAILED"] else 0


if __name__ == "__main__":
    sys.exit(main())
