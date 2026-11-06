"""
Generate X12 5010 837P (professional claim) files from claims that passed the
pre-submission edits (edi.edi_claim_readiness, reject_reason IS NULL).   EDI-1

One file per payer per month of service (claim thru date):
    data/edi/outbound/837P/<PAYER>/837P_<PAYER>_<YYYYMM>.x12
Story: providers in the Coastal Care network submit claims through a clearinghouse
(submitter) to each payer (receiver). EDI-2 parses these files back in as inbound claims.

Usage indicator (ISA15):
    --usage T (default): test files; claims may rely on PROPOSED crosswalk mappings
    --usage P          : production files; only claims whose mappings are ALL APPROVED

Synthetic identifiers (documented, never real):
    * Billing provider NPI: Synthea organizations carry no NPI (H19), so a deterministic
      10-digit NPI with a valid Luhn check digit is derived from the organization id.
    * Billing TIN and payer IDs: deterministic synthetic values.
Rendering provider NPI comes from the EOB care team (H27).

After writing, every file is re-read and validated: segment counts (SE01), control
numbers, HL parent links, and CLM02 = sum of SV102 for every claim. A failure stops the run.

Run from the project root:
    python edi/generate_837p.py --from 2025-01 --to 2025-12
    python edi/generate_837p.py --from 2017-01 --usage P
"""
from __future__ import annotations

import argparse
import hashlib
import logging
import os
import re
import sys
import unicodedata
import uuid
from collections import defaultdict
from datetime import datetime
from decimal import Decimal
from pathlib import Path

import psycopg2
import psycopg2.extras
from dotenv import load_dotenv

OUT_ROOT = Path("data/edi/outbound/837P")     # data/ is git-ignored: files contain (synthetic) PHI
ELEM, SUB, SEG, REP = "*", ":", "~", "^"
SUBMITTER = {"name": "COASTAL CARE CLEARINGHOUSE", "etin": "CCCH00001", "contact": "EDI SUPPORT", "phone": "5615550100"}
FILING_INDICATOR = {"Medicare": "MB", "Dual Eligible": "MB", "Medicaid": "MC"}   # others: CI (commercial)

log = logging.getLogger("gen837p")

DDL = """
CREATE SCHEMA IF NOT EXISTS audit;
CREATE TABLE IF NOT EXISTS audit.edi_file_manifest (
    file_id            UUID PRIMARY KEY,
    run_id             UUID        NOT NULL,
    transaction_set    TEXT        NOT NULL,        -- 837P
    usage_indicator    CHAR(1)     NOT NULL,        -- ISA15
    payer_name         TEXT        NOT NULL,
    service_month      CHAR(7)     NOT NULL,        -- YYYY-MM
    file_path          TEXT        NOT NULL,
    isa_control        INTEGER     NOT NULL,
    claim_count        INTEGER     NOT NULL,
    line_count         INTEGER     NOT NULL,
    total_charge       NUMERIC(14,2) NOT NULL,
    segment_count      INTEGER     NOT NULL,
    file_sha256        CHAR(64)    NOT NULL,
    validated          BOOLEAN     NOT NULL,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
"""

CLAIMS_SQL = """
SELECT r.claim_id, r.payer_name, r.member_source_id, r.provider_id, r.rendering_npi,
       r.place_of_service, r.claim_from_date, r.claim_thru_date, r.billed_amount,
       r.icd10_codes, r.usage_indicator,
       i.first_name, i.last_name, i.address_line, i.city, i.state, i.postal_code,
       m.birth_date, m.sex_code
FROM edi.edi_claim_readiness r
JOIN silver.member m          ON m.source_system = r.source_system AND m.member_source_id = r.member_source_id
JOIN silver.member_identity i ON i.source_system = r.source_system AND i.member_source_id = r.member_source_id
WHERE r.reject_reason IS NULL
  AND r.claim_type = 'PROF'
  AND to_char(r.claim_thru_date, 'YYYY-MM') BETWEEN %(from)s AND %(to)s
  AND (%(usage)s = 'T' OR r.usage_indicator = 'P')
  AND (%(payer)s IS NULL OR r.payer_name = %(payer)s)
ORDER BY r.payer_name, r.claim_thru_date, r.provider_id, r.member_source_id, r.claim_id
"""

LINES_SQL = """
SELECT claim_id, line_sequence, procedure_code, line_charge, service_date
FROM edi.edi_claim_line
WHERE line_role = 'SERVICE' AND claim_id = ANY(%(ids)s)
ORDER BY claim_id, line_sequence
"""

PROVIDERS_SQL = """
SELECT resource_type,
       CASE WHEN resource_type = 'Organization'
            THEN jsonb_path_query_first(resource, '$.identifier[*] ? (@.system == "https://github.com/synthetichealth/synthea").value') #>> '{}'
            ELSE jsonb_path_query_first(resource, '$.identifier[*] ? (@.system == "http://hl7.org/fhir/sid/us-npi").value') #>> '{}'
       END AS ident,
       -- Organization.name is a string; Practitioner.name is a LIST of HumanName objects
       CASE WHEN resource_type = 'Organization' THEN resource ->> 'name'
            ELSE resource #>> '{name,0,family}' END AS name_or_family,
       resource #>> '{name,0,given,0}' AS given,
       resource #>> '{address,0,line,0}' AS address_line,
       resource #>> '{address,0,city}'   AS city,
       resource #>> '{address,0,state}'  AS state,
       resource #>> '{address,0,postalCode}' AS postal_code
FROM bronze.fhir_resource
WHERE resource_type IN ('Organization', 'Practitioner')
"""


# ------------------------------------------------------------------ helpers ---

def get_connection():
    load_dotenv()
    return psycopg2.connect(
        host=os.getenv("PG_HOST", "localhost"), port=os.getenv("PG_PORT", "5432"),
        dbname=os.getenv("PG_DB", "coastal_care"),
        user=os.getenv("PG_USER") or None, password=os.getenv("PG_PASSWORD") or None)


def x12(value, max_len: int | None = None) -> str:
    """X12 basic character set: ASCII uppercase, no delimiter characters."""
    text = unicodedata.normalize("NFKD", str(value or "")).encode("ascii", "ignore").decode()
    text = re.sub(r"[*:~^\r\n]", " ", text).upper().strip()
    text = re.sub(r"\s+", " ", text)
    return text[:max_len].rstrip() if max_len else text   # no trailing spaces after truncation


def luhn_npi(seed: str) -> str:
    """Deterministic synthetic NPI: '1' + 8 digits from a hash + Luhn check digit (prefix 80840)."""
    body = "1" + str(int(hashlib.sha256(seed.encode()).hexdigest(), 16))[:8]
    digits = [int(d) for d in "80840" + body]
    total = 0
    for i, d in enumerate(reversed(digits)):
        if i % 2 == 0:
            d *= 2
            d = d - 9 if d > 9 else d
        total += d
    return body + str((10 - total % 10) % 10)


def npi_is_valid(npi: str) -> bool:
    if not re.fullmatch(r"\d{10}", npi or ""):
        return False
    digits = [int(d) for d in "80840" + npi]
    total = 0
    for i, d in enumerate(reversed(digits)):
        if i % 2 == 1:
            d *= 2
            d = d - 9 if d > 9 else d
        total += d
    return total % 10 == 0


def synthetic_tin(seed: str) -> str:
    return "9" + str(int(hashlib.sha256(("tin" + seed).encode()).hexdigest(), 16))[:8]


def payer_id(name: str) -> str:
    return "CC" + hashlib.sha256(name.encode()).hexdigest()[:5].upper()


def money(value) -> str:
    q = Decimal(value).quantize(Decimal("0.01"))
    return f"{q:f}".rstrip("0").rstrip(".") if q != q.to_integral() else str(int(q))


def zip_code(value) -> str:
    z = re.sub(r"\D", "", str(value or ""))
    return z[:9] if len(z) >= 9 else (z[:5] if len(z) >= 5 else "00000")


# ---------------------------------------------------------------- building ---

class Builder:
    def __init__(self):
        self.segments: list[str] = []

    def add(self, *elements):
        parts = list(elements)
        while parts and parts[-1] in ("", None):       # X12: drop trailing empty elements
            parts.pop()
        self.segments.append(ELEM.join("" if p is None else str(p) for p in parts))


def build_file(payer: str, month: str, claims: list[dict], lines: dict, providers: dict,
               usage: str, isa_control: int, now: datetime) -> tuple[str, dict]:
    b = Builder()
    ctrl = f"{isa_control:09d}"
    b.add("ISA", "00", " " * 10, "00", " " * 10, "ZZ", SUBMITTER["etin"].ljust(15), "ZZ",
          payer_id(payer).ljust(15), now.strftime("%y%m%d"), now.strftime("%H%M"), REP, "00501",
          ctrl, "0", usage, SUB)
    b.add("GS", "HC", SUBMITTER["etin"], payer_id(payer), now.strftime("%Y%m%d"), now.strftime("%H%M"),
          str(isa_control), "X", "005010X222A1")
    st_index = len(b.segments)
    b.add("ST", "837", "0001", "005010X222A1")
    b.add("BHT", "0019", "00", f"{payer_id(payer)}{month.replace('-', '')}", now.strftime("%Y%m%d"),
          now.strftime("%H%M"), "CH")
    b.add("NM1", "41", "2", x12(SUBMITTER["name"], 60), "", "", "", "", "46", SUBMITTER["etin"])
    b.add("PER", "IC", x12(SUBMITTER["contact"]), "TE", SUBMITTER["phone"])
    b.add("NM1", "40", "2", x12(payer, 60), "", "", "", "", "46", payer_id(payer))

    hl = 0
    stats = {"claims": 0, "lines": 0, "charge": Decimal("0"), "invalid_rendering_npi": 0}
    by_provider: dict[str, dict[str, list[dict]]] = defaultdict(lambda: defaultdict(list))
    for c in claims:
        by_provider[c["provider_id"]][c["member_source_id"]].append(c)

    for provider_id, members in by_provider.items():
        org = providers["Organization"].get(provider_id, {})
        hl += 1
        billing_hl = hl
        b.add("HL", str(billing_hl), "", "20", "1")
        b.add("NM1", "85", "2", x12(org.get("name_or_family") or f"PROVIDER {provider_id}", 60),
              "", "", "", "", "XX", luhn_npi(provider_id))
        b.add("N3", x12(org.get("address_line") or "UNKNOWN", 55))
        b.add("N4", x12(org.get("city") or "UNKNOWN", 30), x12(org.get("state") or "FL", 2), zip_code(org.get("postal_code")))
        b.add("REF", "EI", synthetic_tin(provider_id))

        for member_id, member_claims in members.items():
            m = member_claims[0]
            hl += 1
            b.add("HL", str(hl), str(billing_hl), "22", "0")
            b.add("SBR", "P", "18", "", "", "", "", "", "", FILING_INDICATOR.get(payer, "CI"))
            b.add("NM1", "IL", "1", x12(m["last_name"] or "UNKNOWN", 60), x12(m["first_name"], 35),
                  "", "", "", "MI", x12(member_id, 80))
            b.add("N3", x12(m["address_line"] or "UNKNOWN", 55))
            b.add("N4", x12(m["city"] or "UNKNOWN", 30), x12(m["state"] or "FL", 2), zip_code(m["postal_code"]))
            b.add("DMG", "D8", m["birth_date"].strftime("%Y%m%d"), {"M": "M", "F": "F"}.get(m["sex_code"], "U"))
            b.add("NM1", "PR", "2", x12(payer, 60), "", "", "", "", "PI", payer_id(payer))

            for c in member_claims:
                claim_lines = lines.get(c["claim_id"], [])
                total = sum((Decimal(l["line_charge"]) for l in claim_lines), Decimal("0"))
                if total != Decimal(c["billed_amount"]):
                    raise RuntimeError(f"claim {c['claim_id']}: lines {total} != billed {c['billed_amount']}")
                pos = c["place_of_service"] if re.fullmatch(r"\d{2}", c["place_of_service"] or "") else "11"
                b.add("CLM", c["claim_id"][:38], money(total), "", "", f"{pos}{SUB}B{SUB}1", "Y", "A", "Y", "Y")
                dx = c["icd10_codes"][:12]
                b.add("HI", *[f"{'ABK' if i == 0 else 'ABF'}{SUB}{code}" for i, code in enumerate(dx)])
                prac = providers["Practitioner"].get(c["rendering_npi"], {})
                # Send the rendering NPI as received; check-digit validity is a payer edit, so it is
                # counted (data-quality finding), never silently dropped.
                if re.fullmatch(r"\d{10}", c["rendering_npi"] or ""):
                    b.add("NM1", "82", "1", x12(prac.get("name_or_family") or "UNKNOWN", 60),
                          x12(prac.get("given"), 35), "", "", "", "XX", c["rendering_npi"])
                    if not npi_is_valid(c["rendering_npi"]):
                        stats["invalid_rendering_npi"] += 1
                pointers = SUB.join(str(i) for i in range(1, min(len(dx), 4) + 1))
                for n, l in enumerate(claim_lines, 1):
                    b.add("LX", str(n))
                    b.add("SV1", f"HC{SUB}{l['procedure_code']}", money(l["line_charge"]), "UN", "1",
                          "", "", pointers)
                    b.add("DTP", "472", "D8", (l["service_date"] or c["claim_from_date"]).strftime("%Y%m%d"))
                    stats["lines"] += 1
                stats["claims"] += 1
                stats["charge"] += total

    se_count = len(b.segments) - st_index + 1
    b.add("SE", str(se_count), "0001")
    b.add("GE", "1", str(isa_control))
    b.add("IEA", "1", ctrl)
    stats["segments"] = len(b.segments)
    return SEG.join(b.segments) + SEG + "\n", stats


# -------------------------------------------------------------- validation ---

def validate(text: str, expect_claims: int, expect_charge: Decimal) -> list[str]:
    """Re-read the file as a receiver would and check structural and financial rules."""
    errors = []
    segs = [s for s in text.strip().rstrip(SEG).split(SEG)]
    segs = [s.strip("\n") for s in segs]
    ids = [s.split(ELEM)[0] for s in segs]
    if ids[0] != "ISA" or ids[-1] != "IEA":
        errors.append("envelope must start with ISA and end with IEA")
    isa = segs[0].split(ELEM)
    if len(segs[0]) != 105:
        errors.append(f"ISA segment must be 105 characters, got {len(segs[0])}")
    if segs[-1].split(ELEM)[2] != isa[13]:
        errors.append("IEA02 does not match ISA13")
    st, se = ids.index("ST"), ids.index("SE")
    if int(segs[se].split(ELEM)[1]) != se - st + 1:
        errors.append("SE01 segment count is wrong")
    hl_ids, claims, charge = set(), 0, Decimal("0")
    current = None
    for s in segs:
        e = s.split(ELEM)
        if e[0] == "HL":
            if e[2] and e[2] not in hl_ids:
                errors.append(f"HL {e[1]} points to unknown parent {e[2]}")
            hl_ids.add(e[1])
        elif e[0] == "CLM":
            if current and current[1] != current[2]:
                errors.append(f"claim {current[0]}: CLM02 {current[1]} != sum SV102 {current[2]}")
            current = [e[1], Decimal(e[2]), Decimal("0")]
            claims += 1
            charge += Decimal(e[2])
        elif e[0] == "SV1":
            current[2] += Decimal(e[2])
            if not re.fullmatch(r"HC:(\d{5}|\d{4}F|[A-Z]\d{4})", e[1]):
                errors.append(f"bad procedure composite {e[1]}")
        elif e[0] == "HI":
            for comp in e[1:]:
                if not re.fullmatch(r"AB[KF]:[A-Z]\d[0-9A-Z]{1,5}", comp):
                    errors.append(f"bad diagnosis composite {comp}")
    if current and current[1] != current[2]:
        errors.append(f"claim {current[0]}: CLM02 {current[1]} != sum SV102 {current[2]}")
    if claims != expect_claims:
        errors.append(f"claim count {claims} != expected {expect_claims}")
    if charge != expect_charge:
        errors.append(f"total charge {charge} != expected {expect_charge}")
    return errors


# -------------------------------------------------------------------- main ---

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--from", dest="from_", default="2017-01", help="first service month YYYY-MM")
    ap.add_argument("--to", default="2099-12", help="last service month YYYY-MM")
    ap.add_argument("--usage", choices=["T", "P"], default="T", help="ISA15 usage indicator")
    ap.add_argument("--payer", default=None, help="only this payer name")
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s", datefmt="%H:%M:%S")

    conn = get_connection()
    conn.autocommit = True
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute(DDL)
    cur.execute(CLAIMS_SQL, {"from": args.from_, "to": args.to, "usage": args.usage, "payer": args.payer})
    claims = cur.fetchall()
    if not claims:
        log.warning("No READY professional claims for this window/usage. Nothing written.")
        return 0
    cur.execute(LINES_SQL, {"ids": [c["claim_id"] for c in claims]})
    lines = defaultdict(list)
    for l in cur.fetchall():
        lines[l["claim_id"]].append(l)
    cur.execute(PROVIDERS_SQL)
    providers = {"Organization": {}, "Practitioner": {}}
    for p in cur.fetchall():
        if p["ident"]:
            providers[p["resource_type"]][p["ident"]] = p
    cur.execute("SELECT coalesce(max(isa_control), 0) AS last FROM audit.edi_file_manifest")
    isa_control = cur.fetchone()["last"]

    groups = defaultdict(list)
    for c in claims:
        groups[(c["payer_name"], c["claim_thru_date"].strftime("%Y-%m"))].append(c)

    run_id, now = uuid.uuid4(), datetime.now()
    totals = {"files": 0, "claims": 0, "charge": Decimal("0"), "invalid_npi": 0}
    for (payer, month), group in sorted(groups.items()):
        isa_control += 1
        text, stats = build_file(payer, month, group, lines, providers, args.usage, isa_control, now)
        expected_charge = sum((Decimal(c["billed_amount"]) for c in group), Decimal("0"))
        errors = validate(text, len(group), expected_charge)
        if errors:
            log.error("FAIL %s %s: %s", payer, month, "; ".join(errors[:5]))
            return 1
        safe = re.sub(r"[^A-Za-z0-9]+", "_", payer).strip("_").upper()
        path = OUT_ROOT / safe / f"837P_{safe}_{month.replace('-', '')}_{args.usage}.x12"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="ascii")
        cur.execute(
            """INSERT INTO audit.edi_file_manifest (file_id, run_id, transaction_set, usage_indicator, payer_name,
                   service_month, file_path, isa_control, claim_count, line_count, total_charge, segment_count,
                   file_sha256, validated)
               VALUES (%s,%s,'837P',%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,true)""",
            (str(uuid.uuid4()), str(run_id), args.usage, payer, month, str(path), isa_control,
             stats["claims"], stats["lines"], stats["charge"], stats["segments"],
             hashlib.sha256(text.encode()).hexdigest()))
        totals["files"] += 1
        totals["claims"] += stats["claims"]
        totals["charge"] += stats["charge"]
        totals["invalid_npi"] += stats["invalid_rendering_npi"]

    expected = sum((Decimal(c["billed_amount"]) for c in claims), Decimal("0"))
    if totals["claims"] != len(claims) or totals["charge"] != expected:
        log.error("Run reconciliation failed: files %s claims / $%s vs ready %s / $%s",
                  totals["claims"], totals["charge"], len(claims), expected)
        return 1
    print(f"\nRun {run_id}: {totals['files']} files, {totals['claims']:,} claims, "
          f"${totals['charge']:,.2f} (ISA15={args.usage}) - all files validated and reconciled")
    if totals["invalid_npi"]:
        print(f"Data quality: {totals['invalid_npi']:,} claims carry a rendering NPI that fails the "
              f"NPI check digit (sent as received; a payer would reject them)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
