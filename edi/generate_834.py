"""
Generate X12 5010 834 benefit enrollment and maintenance files.   EDI-4

The payer's enrollment system tells the plan WHO is covered, BY WHICH plan, FROM and TO when.
Source: Synthea coverage history (bronze.synthea_payer_transitions, loaded as exported), with
the subscriber's demographics from silver.member_identity.

One file per payer (full-file replacement of the enrollment window), one INS loop per
coverage span:
    INS*Y*18*021*28*A     subscriber, self, addition, initial enrollment, active
    REF*0F                subscriber ID = the PAYER's member ID (never our member ID)
    NM1*IL / N3 / N4 / DMG  name, SSN, address, birth date, sex: what the MPI matches on
    HD*021**HLT           health coverage
    DTP*348 / DTP*349     benefit begin / end

Documented simplifications (docs/profiling/edi_findings.md H38-H40):
  * every covered person is sent as a subscriber (Synthea gives no subscriber ID for
    dependents, only the owner's name), so INS01=Y, INS02=18 for all;
  * NO_INSURANCE spans are not coverage and are not sent;
  * secondary payers (COB, loop 2320) are not sent.

The answer key (payer member ID -> true member) goes to audit.mpi_test_truth so the MPI
can be measured on enrollment too; the window and span count per file go to
audit.edi_file_manifest so dbt can prove the round trip.

    data/edi/outbound/834/834_<PAYER>_<usage>.x12
Run:  python edi/generate_834.py --from 2016-01
"""
from __future__ import annotations

import argparse
import hashlib
import logging
import re
import sys
import uuid
from collections import defaultdict
from datetime import datetime
from decimal import Decimal
from pathlib import Path

import psycopg2.extras

from generate_837p import REP, SEG, SUB, Builder, get_connection, payer_id, synthetic_tin, x12, zip_code, DDL as MANIFEST_DDL

OUT_ROOT = Path("data/edi/outbound/834")
SPONSOR = {"name": "COASTAL CARE HEALTH PLAN", "tin": "900000001"}
log = logging.getLogger("gen834")

SPANS_SQL = """
SELECT t.memberid, t.patient AS member_source_id, p.name AS payer_name,
       left(t.start_date, 10)::date AS begin_date, nullif(left(t.end_date, 10), '')::date AS end_date,
       i.first_name, i.last_name, i.ssn, i.address_line, i.city, i.state, i.postal_code,
       m.birth_date, m.sex_code
FROM bronze.synthea_payer_transitions t
JOIN bronze.synthea_payers p ON p.id = t.payer
JOIN silver.member_identity i ON i.source_system = 'SYNTHEA_FHIR' AND i.member_source_id = t.patient
JOIN silver.member m ON m.source_system = i.source_system AND m.member_source_id = i.member_source_id
WHERE p.name <> 'NO_INSURANCE'
  AND coalesce(nullif(left(t.end_date, 10), '')::date, '9999-12-31') >= %(from)s::date
ORDER BY p.name, t.memberid, begin_date
"""
SKIPPED_SQL = """
SELECT count(*) FILTER (WHERE p.name = 'NO_INSURANCE')                                   AS self_pay_spans,
       count(*) FILTER (WHERE p.name <> 'NO_INSURANCE' AND i.member_source_id IS NULL)   AS no_member,
       count(*) FILTER (WHERE p.id IS NULL)                                              AS unknown_payer
FROM bronze.synthea_payer_transitions t
LEFT JOIN bronze.synthea_payers p ON p.id = t.payer
LEFT JOIN silver.member_identity i ON i.source_system = 'SYNTHEA_FHIR' AND i.member_source_id = t.patient
WHERE coalesce(nullif(left(t.end_date, 10), '')::date, '9999-12-31') >= %(from)s::date
"""


def clean_name(name) -> str:
    return re.sub(r"\d+", "", name or "").strip()          # Synthea numeric suffixes never reach a payer


def build_file(payer: str, spans: list[dict], usage: str, isa_control: int, now: datetime, window: str) -> tuple[str, dict]:
    b = Builder()
    ctrl = f"{isa_control:09d}"
    pid = payer_id(payer)
    b.add("ISA", "00", " " * 10, "00", " " * 10, "ZZ", pid.ljust(15), "ZZ", "CCCH00001".ljust(15),
          now.strftime("%y%m%d"), now.strftime("%H%M"), REP, "00501", ctrl, "0", usage, SUB)
    b.add("GS", "BE", pid, "CCCH00001", now.strftime("%Y%m%d"), now.strftime("%H%M"), str(isa_control), "X", "005010X220A1")
    st_index = len(b.segments)
    b.add("ST", "834", "0001", "005010X220A1")
    b.add("BGN", "00", f"{pid}{window.replace('-', '')}", now.strftime("%Y%m%d"), now.strftime("%H%M"),
          "", "", "", "4")                                   # BGN08 4 = verify: full file of the window
    b.add("N1", "P5", x12(SPONSOR["name"], 60), "FI", SPONSOR["tin"])
    b.add("N1", "IN", x12(payer, 60), "FI", synthetic_tin(payer)[:9])
    stats = {"spans": 0, "members": len({s["memberid"] for s in spans})}
    for s in spans:
        b.add("INS", "Y", "18", "030", "XN", "A")            # 030 audit/compare (full file), XN notification only
        b.add("REF", "0F", x12(s["memberid"], 50))
        b.add("DTP", "356", "D8", s["begin_date"].strftime("%Y%m%d"))
        ssn = re.sub(r"\D", "", s["ssn"] or "")
        name = ["NM1", "IL", "1", x12(clean_name(s["last_name"]) or "UNKNOWN", 60), x12(clean_name(s["first_name"]), 35)]
        b.add(*(name + (["", "", "", "34", ssn] if len(ssn) == 9 else [])))
        b.add("N3", x12(s["address_line"] or "UNKNOWN", 55))
        b.add("N4", x12(s["city"] or "UNKNOWN", 30), x12(s["state"] or "FL", 2), zip_code(s["postal_code"]))
        b.add("DMG", "D8", s["birth_date"].strftime("%Y%m%d"), {"M": "M", "F": "F"}.get(s["sex_code"], "U"))
        b.add("HD", "030", "", "HLT")
        b.add("DTP", "348", "D8", s["begin_date"].strftime("%Y%m%d"))
        if s["end_date"]:
            b.add("DTP", "349", "D8", s["end_date"].strftime("%Y%m%d"))
        stats["spans"] += 1
    b.add("SE", str(len(b.segments) - st_index + 1), "0001")
    b.add("GE", "1", str(isa_control))
    b.add("IEA", "1", ctrl)
    stats["segments"] = len(b.segments)
    return SEG.join(b.segments) + SEG + "\n", stats


def validate(text: str, expect_spans: int) -> list[str]:
    segs = [s.strip() for s in text.split(SEG) if s.strip()]
    ids = [s.split("*")[0] for s in segs]
    errors = []
    st, se = ids.index("ST"), ids.index("SE")
    if int(segs[se].split("*")[1]) != se - st + 1:
        errors.append("SE01 does not equal the transaction segment count")
    if ids.count("INS") != expect_spans:
        errors.append(f"{ids.count('INS')} INS loops, expected {expect_spans}")
    if ids.count("INS") != sum(1 for s in segs if s.startswith("REF*0F*")):
        errors.append("every INS needs exactly one REF*0F")
    return errors


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--from", dest="from_", default="2016-01", help="first month of the enrollment window YYYY-MM")
    ap.add_argument("--usage", choices=["T", "P"], default="T")
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s", datefmt="%H:%M:%S")
    conn = get_connection()
    conn.autocommit = True
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute(MANIFEST_DDL)
    cur.execute("""CREATE TABLE IF NOT EXISTS audit.mpi_test_truth (source_system TEXT NOT NULL, source_record_id TEXT NOT NULL,
                   true_member_id TEXT NOT NULL, noise TEXT, PRIMARY KEY (source_system, source_record_id))""")
    params = {"from": args.from_ + "-01"}
    cur.execute(SPANS_SQL, params)
    spans = cur.fetchall()
    cur.execute(SKIPPED_SQL, params)
    skipped = cur.fetchone()
    if not spans:
        log.warning("No coverage spans in the window.")
        return 0
    by_payer = defaultdict(list)
    for s in spans:
        by_payer[s["payer_name"]].append(s)
    run_id, now = str(uuid.uuid4()), datetime.now()
    cur.execute("SELECT coalesce(max(isa_control), 0) AS n FROM audit.edi_file_manifest")
    isa = cur.fetchone()["n"]
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    total = 0
    for payer, pspans in sorted(by_payer.items()):
        isa += 1
        text, stats = build_file(payer, pspans, args.usage, isa, now, args.from_)
        errors = validate(text, len(pspans))
        if errors:
            log.error("%s: %s", payer, errors)
            return 1
        path = OUT_ROOT / f"834_{re.sub(r'[^A-Z0-9]+', '_', payer.upper()).strip('_')}_{args.usage}.x12"
        path.write_text(text, encoding="ascii")
        cur.execute("""INSERT INTO audit.edi_file_manifest (file_id, run_id, transaction_set, usage_indicator, payer_name,
                       service_month, file_path, isa_control, claim_count, line_count, total_charge, segment_count,
                       file_sha256, validated) VALUES (%s,%s,'834',%s,%s,%s,%s,%s,%s,%s,0,%s,%s,true)""",
                    (str(uuid.uuid4()), run_id, args.usage, payer, args.from_, str(path), isa, stats["spans"],
                     stats["members"], stats["segments"], hashlib.sha256(text.encode()).hexdigest()))
        total += stats["spans"]
    psycopg2.extras.execute_values(cur, """INSERT INTO audit.mpi_test_truth VALUES %s
        ON CONFLICT (source_system, source_record_id) DO UPDATE SET true_member_id = EXCLUDED.true_member_id""",
        list({("X12_834", x12(s["memberid"], 50), s["member_source_id"], None) for s in spans}))   # as sent (X12 uppercase)
    print(f"\nRun {run_id}: {len(by_payer)} files, {total:,} coverage spans, "
          f"{len({s['memberid'] for s in spans}):,} payer member IDs (window from {args.from_}, ISA15={args.usage})")
    print(f"Not sent: {skipped['self_pay_spans']:,} NO_INSURANCE spans, {skipped['no_member']:,} spans for people "
          f"without a FHIR record, {skipped['unknown_payer']:,} spans with an unknown payer")
    return 0


if __name__ == "__main__":
    sys.exit(main())
