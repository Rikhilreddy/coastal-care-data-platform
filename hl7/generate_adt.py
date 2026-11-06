"""
Generate HL7 v2.5.1 ADT messages for inpatient stays: A01 (admit) and A03 (discharge).   HL7-1

Source: FHIR Encounters of class IMP / ACUTE / NONAC (inpatient), with the patient's
demographics from silver.member_identity and the attending NPI from the encounter.

Realism that the MPI (patient matching) must handle, as in real hospital feeds:
  * The hospital sends ITS OWN medical record number (facility MRN), never our member ID.
  * Names are entered by registration staff: Synthea's numeric suffixes are absent, and a
    small, SEEDED share of messages carry data-entry noise:
        ~2% last-name typo (two letters swapped)   ~3% SSN not collected
        ~1% birth date keyed one day off
  * The answer key (which member each facility MRN really is) is written to
    audit.mpi_test_truth so match accuracy can be measured; it is never used for matching.

Output: data/hl7/outbound/adt/ADT_<YYYYMM>.hl7 (batch of messages, segments end with \\r,
messages separated by \\n), one file per month of admission.

Run:  python hl7/generate_adt.py --from 2017-01
"""
from __future__ import annotations

import argparse
import hashlib
import logging
import os
import random
import re
import sys
from collections import defaultdict
from pathlib import Path

import psycopg2
import psycopg2.extras
from dotenv import load_dotenv

OUT_ROOT = Path("data/hl7/outbound/adt")
SENDING_APP, RECEIVING_APP, RECEIVING_FAC = "COASTAL_EHR", "COASTAL_DP", "COASTAL_CARE"
log = logging.getLogger("gen_adt")

ENCOUNTERS_SQL = """
SELECT e.resource_id AS encounter_id,
       regexp_replace(e.resource #>> '{subject,reference}', '^(urn:uuid:|Patient/)', '') AS member_source_id,
       e.resource #>> '{period,start}' AS start_ts, e.resource #>> '{period,end}' AS end_ts,
       regexp_replace(coalesce(e.resource #>> '{participant,0,individual,reference}', ''), '^.*\\|', '') AS attending_npi,
       regexp_replace(coalesce(e.resource #>> '{serviceProvider,reference}', ''), '^.*\\|', '') AS facility_id,
       coalesce(e.resource #>> '{serviceProvider,display}', 'COASTAL HOSPITAL') AS facility_name,
       i.first_name, i.last_name, i.ssn, i.address_line, i.city, i.state, i.postal_code, i.phone,
       m.birth_date, m.sex_code
FROM bronze.fhir_resource e
JOIN silver.member_identity i ON i.source_system = 'SYNTHEA_FHIR'
     AND i.member_source_id = regexp_replace(e.resource #>> '{subject,reference}', '^(urn:uuid:|Patient/)', '')
JOIN silver.member m ON m.source_system = i.source_system AND m.member_source_id = i.member_source_id
WHERE e.resource_type = 'Encounter'
  AND e.resource #>> '{class,code}' IN ('IMP', 'ACUTE', 'NONAC')
  AND to_char(left(e.resource #>> '{period,start}', 10)::date, 'YYYY-MM') BETWEEN %(from)s AND %(to)s
ORDER BY start_ts, encounter_id
"""
TRUTH_DDL = """
CREATE SCHEMA IF NOT EXISTS audit;
CREATE TABLE IF NOT EXISTS audit.mpi_test_truth (
    source_system     TEXT NOT NULL,      -- HL7_ADT, X12_834
    source_record_id  TEXT NOT NULL,      -- facility MRN / subscriber ID as sent
    true_member_id    TEXT NOT NULL,      -- the FHIR member it really is (answer key)
    noise             TEXT,               -- which perturbation was applied, if any
    PRIMARY KEY (source_system, source_record_id)
);
"""


def get_connection():
    load_dotenv()
    return psycopg2.connect(host=os.getenv("PG_HOST", "localhost"), port=os.getenv("PG_PORT", "5432"),
                            dbname=os.getenv("PG_DB", "coastal_care"),
                            user=os.getenv("PG_USER") or None, password=os.getenv("PG_PASSWORD") or None)


def hl7(value) -> str:
    """Escape HL7 delimiters | ^ ~ \\ & and strip Synthea's numeric name suffixes."""
    text = str(value or "")
    return (text.replace("\\", "\\E\\").replace("|", "\\F\\").replace("^", "\\S\\")
                .replace("~", "\\R\\").replace("&", "\\T\\"))


def clean_name(name: str) -> str:
    return re.sub(r"\d+", "", name or "").strip().upper()


def ts(fhir_ts: str | None) -> str:
    """FHIR dateTime -> HL7 DTM (YYYYMMDDHHMMSS), local time as recorded."""
    if not fhir_ts:
        return ""
    return re.sub(r"\D", "", fhir_ts[:19])[:14]


def facility_mrn(member_id: str, facility_id: str) -> str:
    return "M" + hashlib.sha256(f"{facility_id}|{member_id}".encode()).hexdigest()[:9].upper()


def perturb(rnd: random.Random, last: str, ssn: str | None, dob) -> tuple[str, str | None, object, str | None]:
    noise = []
    if len(last) > 3 and rnd.random() < 0.02:
        k = rnd.randrange(1, len(last) - 1)
        last = last[:k] + last[k + 1] + last[k] + last[k + 2:]
        noise.append("LAST_NAME_TYPO")
    if ssn and rnd.random() < 0.03:
        ssn = None
        noise.append("SSN_MISSING")
    if dob and rnd.random() < 0.01:
        from datetime import timedelta
        dob = dob + timedelta(days=1)
        noise.append("DOB_OFF_BY_ONE")
    return last, ssn, dob, (",".join(noise) or None)


def pv1(e: dict, event: str) -> str:
    """PV1 built by FIELD NUMBER (never by counting pipes): 2 class, 3 location,
    7 attending, 19 visit number, 44 admit, 45 discharge."""
    f = [""] * 46
    f[1], f[2] = "1", "I"
    f[3] = "INPATIENT^^^" + hl7(e["facility_name"][:20].upper())
    f[7] = f"{e['attending_npi']}^^^^^^^^NPI" if e["attending_npi"] else ""
    f[19] = e["encounter_id"]
    f[44] = ts(e["start_ts"])
    f[45] = ts(e["end_ts"]) if event == "A03" else ""
    while f and f[-1] == "":
        f.pop()
    return "PV1|" + "|".join(f[1:])


def message(event: str, ctrl: str, e: dict, pid: dict) -> str:
    """MSH-7 = event time, so regenerating the same data gives byte-identical files (idempotent loads)."""
    event_ts = ts(e["start_ts"]) if event == "A01" else ts(e["end_ts"])
    segs = [
        f"MSH|^~\\&|{SENDING_APP}|{hl7(e['facility_name'][:20].upper())}|{RECEIVING_APP}|{RECEIVING_FAC}|"
        f"{event_ts}||ADT^{event}^ADT_{event}|{ctrl}|T|2.5.1",
        f"EVN|{event}|{event_ts}",
        "PID|1||" + pid["mrn"] + "^^^" + SENDING_APP + "^MR" + (f"~{pid['ssn']}^^^SSA^SS" if pid["ssn"] else "")
        + f"||{hl7(pid['last'])}^{hl7(pid['first'])}||{pid['dob']}|{pid['sex']}|||"
        + f"{hl7(pid['address'])}^^{hl7(pid['city'])}^{pid['state']}^{pid['zip']}||{hl7(pid['phone'])}",
        pv1(e, event),
    ]
    return "\r".join(segs) + "\r"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--from", dest="from_", default="2017-01")
    ap.add_argument("--to", default="2099-12")
    ap.add_argument("--seed", type=int, default=20261103, help="noise seed (same seed = same files)")
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s", datefmt="%H:%M:%S")
    conn = get_connection()
    conn.autocommit = True
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute(TRUTH_DDL)
    cur.execute(ENCOUNTERS_SQL, {"from": args.from_, "to": args.to})
    encounters = cur.fetchall()
    if not encounters:
        log.warning("No inpatient encounters in this window.")
        return 0
    by_month = defaultdict(list)
    truth, n_msgs = {}, 0
    for e in encounters:
        mrn = facility_mrn(e["member_source_id"], e["facility_id"])
        rnd = random.Random(f"{args.seed}|{mrn}")      # noise is per registration (MRN), like a real EHR
        last, ssn, dob, noise = perturb(rnd, clean_name(e["last_name"]), e["ssn"], e["birth_date"])
        pid = {"mrn": mrn, "ssn": (ssn or "").replace("-", "") or None, "last": last,
               "first": clean_name(e["first_name"]), "dob": dob.strftime("%Y%m%d") if dob else "",
               "sex": e["sex_code"] or "U", "address": (e["address_line"] or "").upper(),
               "city": (e["city"] or "").upper(), "state": e["state"] or "", "zip": (e["postal_code"] or "")[:5],
               "phone": e["phone"] or ""}
        truth.setdefault(mrn, (e["member_source_id"], noise))
        month = e["start_ts"][:7]
        for event in ("A01", "A03"):
            n_msgs += 1
            ctrl = hashlib.sha256(f"{event}|{e['encounter_id']}".encode()).hexdigest()[:20].upper()
            by_month[month].append(message(event, ctrl, e, pid))
    for month, msgs in sorted(by_month.items()):
        path = OUT_ROOT / f"ADT_{month.replace('-', '')}.hl7"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("\n".join(msgs), encoding="ascii", errors="replace")
    psycopg2.extras.execute_values(cur, """INSERT INTO audit.mpi_test_truth VALUES %s
        ON CONFLICT (source_system, source_record_id) DO UPDATE SET true_member_id = EXCLUDED.true_member_id,
        noise = EXCLUDED.noise""", [("HL7_ADT", k, v[0], v[1]) for k, v in truth.items()])
    noisy = sum(1 for v in truth.values() if v[1])
    print(f"\n{len(by_month)} files, {len(encounters):,} inpatient stays, {n_msgs:,} ADT messages "
          f"({len(truth):,} facility MRNs; {noisy} carry seeded data-entry noise)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
