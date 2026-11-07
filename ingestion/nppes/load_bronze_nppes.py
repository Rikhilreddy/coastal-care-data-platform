"""
Verify provider NPIs against the CMS NPPES NPI Registry API (free, public, no key).   API-1

Why: every claim names providers by NPI. A payer rejects an NPI that is malformed, fails the
check digit, or is not an active registered provider. This pipeline checks every NPI on our
claims and lands the registry's answer in bronze, exactly as returned (JSON).

Design (object-oriented, each class has one job):
    NPI                  value object: format + Luhn check digit (prefix 80840), no network
    Transport            interface for "get JSON for an NPI"
      HttpTransport      the real API: timeout, polite rate limit, retries with backoff
      FixtureTransport   canned responses from a JSON file (CI and offline tests)
    NppesClient          turns a response into a LookupResult (FOUND / NOT_FOUND / API_ERROR)
    NppesLoader          picks the work (watermark), calls the client, writes bronze + audit

Watermark (incremental): audit.etl_watermark keeps, per pipeline, the load time of the newest
claim batch already fully processed. A run only looks at NPIs on claims loaded AFTER it, plus
any NPI never checked. The watermark moves forward only when that work is fully done, so a
run stopped by --limit or an outage resumes where it left off (nothing skipped).

Malformed NPIs and NPIs failing the check digit are recorded WITHOUT calling the API.

Run from the project root:
    python ingestion/nppes/load_bronze_nppes.py --limit 200
    python ingestion/nppes/load_bronze_nppes.py --fixture ci/fixtures/nppes_responses.json   # offline
"""
from __future__ import annotations

import argparse
import json
import logging
import os
import sys
import time
import uuid
from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import psycopg2
import psycopg2.extras
import requests
from dotenv import load_dotenv

API_URL = "https://npiregistry.cms.hhs.gov/api/"
PIPELINE = "nppes_npi_lookup"
DDL = """
CREATE SCHEMA IF NOT EXISTS bronze;
CREATE TABLE IF NOT EXISTS bronze.nppes_npi_lookup (
    npi            TEXT        NOT NULL,
    lookup_status  TEXT        NOT NULL,      -- FOUND, NOT_FOUND, INVALID_FORMAT, INVALID_CHECK_DIGIT, API_ERROR
    http_status    INTEGER,
    result_count   INTEGER,
    response       JSONB,                     -- the registry's answer exactly as returned
    error_message  TEXT,
    fetched_at     TIMESTAMPTZ NOT NULL,
    _batch_id      UUID        NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_nppes_npi ON bronze.nppes_npi_lookup (npi, fetched_at DESC);
CREATE SCHEMA IF NOT EXISTS audit;
CREATE TABLE IF NOT EXISTS audit.etl_watermark (
    pipeline         TEXT PRIMARY KEY,
    high_water_mark  TIMESTAMPTZ,             -- newest source batch fully processed
    last_run_at      TIMESTAMPTZ NOT NULL,
    last_run_rows    INTEGER     NOT NULL,
    last_run_status  TEXT        NOT NULL
);
"""
# NPIs on claims, with the load time of the claim batch they came from (the watermark column).
CANDIDATES_SQL = """
WITH npis AS (
    SELECT n.npi, m.finished_at AS batch_loaded_at
    FROM silver.claim_header c
    LEFT JOIN audit.load_manifest m ON m.batch_id = c._batch_id
    CROSS JOIN LATERAL (VALUES (c.attending_npi), (c.operating_npi), (c.other_npi)) n(npi)
    WHERE nullif(trim(n.npi), '') IS NOT NULL
    UNION ALL
    SELECT r.rendering_npi, NULL::timestamptz FROM edi.edi_claim_readiness r
    WHERE nullif(trim(r.rendering_npi), '') IS NOT NULL
)
SELECT npi, max(batch_loaded_at) AS batch_loaded_at, count(*) AS claim_refs
FROM npis
GROUP BY npi
HAVING max(batch_loaded_at) > %(watermark)s                       -- on a claim batch newer than the watermark
    OR NOT EXISTS (SELECT 1 FROM bronze.nppes_npi_lookup l WHERE l.npi = npis.npi)   -- or never checked
ORDER BY count(*) DESC, npi
"""
log = logging.getLogger("nppes")


# ------------------------------------------------------------------ domain ---

@dataclass(frozen=True)
class NPI:
    value: str

    @property
    def well_formed(self) -> bool:
        return len(self.value) == 10 and self.value.isdigit() and self.value[0] in "12"

    @property
    def check_digit_ok(self) -> bool:
        """Luhn over '80840' + NPI (the NPI standard's card-issuer prefix)."""
        total = 0
        for i, ch in enumerate(reversed("80840" + self.value)):
            d = int(ch)
            if i % 2 == 1:
                d = d * 2 - 9 if d * 2 > 9 else d * 2
            total += d
        return total % 10 == 0


@dataclass
class LookupResult:
    npi: str
    status: str
    http_status: int | None = None
    result_count: int | None = None
    response: dict | None = None
    error: str | None = None


# --------------------------------------------------------------- transport ---

class Transport(ABC):
    @abstractmethod
    def get(self, npi: str) -> tuple[int, dict]:
        """Return (http_status, json_body) for one NPI."""


class HttpTransport(Transport):
    def __init__(self, timeout: float = 15, per_second: float = 3, retries: int = 3):
        self.session = requests.Session()
        self.session.headers["User-Agent"] = "coastal-care-data-platform/1.0 (portfolio project)"
        self.timeout, self.min_gap, self.retries = timeout, 1 / per_second, retries
        self._last = 0.0

    def get(self, npi: str) -> tuple[int, dict]:
        for attempt in range(1, self.retries + 1):
            wait = self.min_gap - (time.monotonic() - self._last)      # polite rate limit
            if wait > 0:
                time.sleep(wait)
            self._last = time.monotonic()
            try:
                r = self.session.get(API_URL, params={"version": "2.1", "number": npi}, timeout=self.timeout)
                if r.status_code in (429, 500, 502, 503, 504) and attempt < self.retries:
                    raise requests.HTTPError(f"HTTP {r.status_code}")
                return r.status_code, r.json()
            except (requests.RequestException, ValueError) as exc:
                if attempt == self.retries:
                    raise
                backoff = 2 ** attempt
                log.warning("NPI %s attempt %s failed (%s); retrying in %ss", npi, attempt, exc, backoff)
                time.sleep(backoff)
        raise RuntimeError("unreachable")


class FixtureTransport(Transport):
    """Offline responses keyed by NPI; an NPI not in the file is 'not found'."""

    def __init__(self, path: Path):
        self.responses = json.loads(path.read_text())

    def get(self, npi: str) -> tuple[int, dict]:
        return 200, self.responses.get(npi, {"result_count": 0, "results": []})


# ------------------------------------------------------------------ client ---

class NppesClient:
    def __init__(self, transport: Transport):
        self.transport = transport

    def lookup(self, raw: str) -> LookupResult:
        npi = NPI(raw.strip())
        if not npi.well_formed:
            return LookupResult(npi.value, "INVALID_FORMAT")
        if not npi.check_digit_ok:
            return LookupResult(npi.value, "INVALID_CHECK_DIGIT")     # a payer rejects it: no API call
        try:
            status, body = self.transport.get(npi.value)
        except Exception as exc:                                       # outage: record it, retry next run
            return LookupResult(npi.value, "API_ERROR", error=str(exc)[:500])
        if status != 200 or "Errors" in body:
            return LookupResult(npi.value, "API_ERROR", status, None, body, json.dumps(body.get("Errors"))[:500])
        count = int(body.get("result_count") or 0)
        return LookupResult(npi.value, "FOUND" if count else "NOT_FOUND", status, count, body)


# ------------------------------------------------------------------ loader ---

class NppesLoader:
    def __init__(self, conn, client: NppesClient, limit: int):
        self.conn, self.client, self.limit = conn, client, limit
        self.batch_id = str(uuid.uuid4())

    def watermark(self, cur) -> datetime:
        cur.execute("SELECT high_water_mark FROM audit.etl_watermark WHERE pipeline = %s", (PIPELINE,))
        row = cur.fetchone()
        return row[0] if row and row[0] else datetime(1900, 1, 1, tzinfo=timezone.utc)

    def run(self) -> dict:
        with self.conn.cursor() as cur:
            cur.execute(DDL)
            wm = self.watermark(cur)
            cur.execute(CANDIDATES_SQL, {"watermark": wm})
            candidates = cur.fetchall()
        work = candidates[: self.limit]
        counts: dict[str, int] = {}
        rows = []
        for n, (npi, _, _) in enumerate(work, 1):
            res = self.client.lookup(npi)
            counts[res.status] = counts.get(res.status, 0) + 1
            rows.append((res.npi, res.status, res.http_status, res.result_count,
                         psycopg2.extras.Json(res.response) if res.response is not None else None,
                         res.error, datetime.now(timezone.utc), self.batch_id))
            if n % 50 == 0:
                log.info("%s / %s NPIs checked", n, len(work))
        drained = len(work) == len(candidates) and counts.get("API_ERROR", 0) == 0
        new_wm = max([wm] + [c[1] for c in work if c[1] is not None]) if drained else wm
        with self.conn, self.conn.cursor() as cur:                     # one transaction: rows + watermark
            psycopg2.extras.execute_values(cur, """INSERT INTO bronze.nppes_npi_lookup (npi, lookup_status,
                http_status, result_count, response, error_message, fetched_at, _batch_id) VALUES %s""", rows)
            cur.execute("""INSERT INTO audit.etl_watermark VALUES (%s, %s, now(), %s, %s)
                ON CONFLICT (pipeline) DO UPDATE SET high_water_mark = EXCLUDED.high_water_mark,
                last_run_at = EXCLUDED.last_run_at, last_run_rows = EXCLUDED.last_run_rows,
                last_run_status = EXCLUDED.last_run_status""",
                (PIPELINE, new_wm, len(rows),
                 "COMPLETE" if drained else "PARTIAL"))
        return {"candidates": len(candidates), "checked": len(rows), "remaining": len(candidates) - len(rows),
                "watermark_before": wm, "watermark_after": new_wm, **counts}


def get_connection():
    load_dotenv()
    return psycopg2.connect(host=os.getenv("PG_HOST", "localhost"), port=os.getenv("PG_PORT", "5432"),
                            dbname=os.getenv("PG_DB", "coastal_care"),
                            user=os.getenv("PG_USER") or None, password=os.getenv("PG_PASSWORD") or None)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--limit", type=int, default=200, help="max NPIs per run (be polite to a free public API)")
    ap.add_argument("--fixture", type=Path, help="offline JSON responses instead of the live API")
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s", datefmt="%H:%M:%S")
    transport = FixtureTransport(args.fixture) if args.fixture else HttpTransport()
    conn = get_connection()
    try:
        stats = NppesLoader(conn, NppesClient(transport), args.limit).run()
    finally:
        conn.close()
    print("\n" + "  ".join(f"{k}={v}" for k, v in stats.items()))
    return 1 if stats.get("API_ERROR") else 0


if __name__ == "__main__":
    sys.exit(main())
