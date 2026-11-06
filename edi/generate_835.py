"""
Generate X12 5010 835 (health care claim payment / remittance advice) files.   EDI-3

The payer's answer to the 837: for every claim it RECEIVED (edi.edi_inbound_837p_claim),
what it paid, per claim and per service line, and why the rest was not paid.
Amounts come from the FHIR ExplanationOfBenefit (H11, H24), bundled exactly like the 837
lines so every 835 service line matches an 837 service line.

Balancing (enforced and re-validated per line, claim and payment):
    line charge  = line paid + CAS adjustments
        CAS*PR*1  deductible            (patient responsibility)
        CAS*PR*2  coinsurance           (patient responsibility)
        CAS*CO*45 charge above the contracted amount (the rest)
    CLP03 = sum SVC02 (charge)   CLP04 = sum SVC03 (paid)   BPR02 = sum CLP04 per payee

One file per payer per service month; one ST/SE transaction (one payment, BPR) per payee
(billing provider) inside it, as payers remit per provider.
    data/edi/outbound/835/<PAYER>/835_<PAYER>_<YYYYMM>_<usage>.x12

Run from the project root (after the 837s are loaded and dbt is built):
    python edi/generate_835.py --from 2025-01 --to 2025-12
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

from generate_837p import (ELEM, REP, SEG, SUB, FILING_INDICATOR, Builder, get_connection, luhn_npi,
                           money, payer_id, synthetic_tin, x12, zip_code, DDL as MANIFEST_DDL)

OUT_ROOT = Path("data/edi/outbound/835")
# CLP06 uses the 835 code list, which differs from the 837 SBR09 list: 'CI' (commercial) is
# valid on the 837 but not on the 835, where commercial plans are reported by plan type.
REMIT_FILING_INDICATOR = {"Medicare": "MB", "Dual Eligible": "MB", "Medicaid": "MC"}   # others: 12 (PPO)
log = logging.getLogger("gen835")

CLAIMS_SQL = """
SELECT i.claim_id, i.usage_indicator, i.payer_name AS payer_x12, r.payer_name, r.provider_id,
       i.member_source_id, i.last_name, i.first_name, r.claim_from_date, r.claim_thru_date, r.billed_amount
FROM edi.edi_inbound_837p_claim i
JOIN edi.edi_claim_readiness r ON r.claim_id = i.claim_id
WHERE to_char(r.claim_thru_date, 'YYYY-MM') BETWEEN %(from)s AND %(to)s
ORDER BY r.payer_name, r.claim_thru_date, r.provider_id, i.claim_id
"""
LINES_SQL = """
SELECT claim_id, line_sequence, procedure_code, line_charge, line_paid, line_deductible, line_coinsurance, service_date
FROM edi.edi_claim_line
WHERE line_role = 'SERVICE' AND claim_id = ANY(%(ids)s)
ORDER BY claim_id, line_sequence
"""
ORGS_SQL = """
SELECT jsonb_path_query_first(resource, '$.identifier[*] ? (@.system == "https://github.com/synthetichealth/synthea").value') #>> '{}' AS ident,
       resource ->> 'name' AS name, resource #>> '{address,0,line,0}' AS address_line,
       resource #>> '{address,0,city}' AS city, resource #>> '{address,0,state}' AS state,
       resource #>> '{address,0,postalCode}' AS postal_code
FROM bronze.fhir_resource WHERE resource_type = 'Organization'
"""


def line_adjustments(l) -> tuple[Decimal, Decimal, Decimal, Decimal, Decimal]:
    charge, paid = Decimal(l["line_charge"]), Decimal(l["line_paid"])
    ded, coins = Decimal(l["line_deductible"]), Decimal(l["line_coinsurance"])
    contractual = charge - paid - ded - coins          # the remainder, so the line always balances
    if contractual < 0:                                # paid + patient share above charge: cap patient share
        coins = max(Decimal("0"), coins + contractual)
        contractual = charge - paid - ded - coins
        if contractual < 0:
            ded = max(Decimal("0"), ded + contractual)
            contractual = charge - paid - ded - coins
    return charge, paid, ded, coins, contractual


def build_file(payer, month, claims, lines, orgs, usage, isa_control, now):
    b = Builder()
    ctrl = f"{isa_control:09d}"
    pid = payer_id(payer)
    b.add("ISA", "00", " " * 10, "00", " " * 10, "ZZ", pid.ljust(15), "ZZ", "CCCH00001".ljust(15),
          now.strftime("%y%m%d"), now.strftime("%H%M"), REP, "00501", ctrl, "0", usage, SUB)
    b.add("GS", "HP", pid, "CCCH00001", now.strftime("%Y%m%d"), now.strftime("%H%M"), str(isa_control), "X", "005010X221A1")
    by_payee = defaultdict(list)
    for c in claims:
        by_payee[c["provider_id"]].append(c)
    stats = {"payments": 0, "claims": 0, "lines": 0, "paid": Decimal("0"), "charge": Decimal("0")}
    for n_st, (provider_id, payee_claims) in enumerate(sorted(by_payee.items()), 1):
        st_index = len(b.segments)
        st_ctrl = f"{n_st:04d}"
        org = orgs.get(provider_id, {})
        # compute claim totals first: BPR (payment) comes before the claims
        claim_rows, payment = [], Decimal("0")
        for c in payee_claims:
            ls = [line_adjustments(l) + (l,) for l in lines.get(c["claim_id"], [])]
            paid = sum((x[1] for x in ls), Decimal("0"))
            charge = sum((x[0] for x in ls), Decimal("0"))
            if charge != Decimal(c["billed_amount"]):
                raise RuntimeError(f"claim {c['claim_id']}: 835 charge {charge} != billed {c['billed_amount']}")
            claim_rows.append((c, ls, charge, paid))
            payment += paid
        trace = f"{pid}{month.replace('-', '')}{n_st:04d}"
        b.add("ST", "835", st_ctrl)                      # ST03 is "Not Used" in the 835 (required in the 837)
        b.add("BPR", "I", money(payment), "C", "NON", "", "", "", "", "", "", "", "", "", "", "",
              now.strftime("%Y%m%d"))                                  # NON: remittance only, synthetic payment
        b.add("TRN", "1", trace, "1" + synthetic_tin(payer)[:9])
        b.add("DTM", "405", now.strftime("%Y%m%d"))
        b.add("N1", "PR", x12(payer, 60))
        b.add("N3", "1 PAYER PLAZA")
        b.add("N4", "TAMPA", "FL", "33602")
        b.add("PER", "BL", "EDI SUPPORT", "TE", "8005550100")
        b.add("N1", "PE", x12(org.get("name") or f"PROVIDER {provider_id}", 60), "XX", luhn_npi(provider_id))
        b.add("N3", x12(org.get("address_line") or "UNKNOWN", 55))
        b.add("N4", x12(org.get("city") or "UNKNOWN", 30), x12(org.get("state") or "FL", 2), zip_code(org.get("postal_code")))
        b.add("REF", "TJ", synthetic_tin(provider_id))
        b.add("LX", "1")
        for c, ls, charge, paid in claim_rows:
            patient_resp = sum((x[2] + x[3] for x in ls), Decimal("0"))
            status = "1" if paid > 0 else ("4" if patient_resp == 0 else "1")   # 4 = denied
            b.add("CLP", c["claim_id"][:38], status, money(charge), money(paid), money(patient_resp),
                  REMIT_FILING_INDICATOR.get(c["payer_name"], "12"),
                  hashlib.sha256(c["claim_id"].encode()).hexdigest()[:15].upper())
            b.add("NM1", "QC", "1", x12(c["last_name"] or "UNKNOWN", 60), x12(c["first_name"], 35),
                  "", "", "", "MI", x12(c["member_source_id"], 80))
            b.add("DTM", "232", c["claim_from_date"].strftime("%Y%m%d"))
            for line_charge, line_paid, ded, coins, contractual, l in ls:
                b.add("SVC", f"HC{SUB}{l['procedure_code']}", money(line_charge), money(line_paid), "", "1")
                b.add("DTM", "472", (l["service_date"] or c["claim_from_date"]).strftime("%Y%m%d"))
                pr = [(code, amt) for code, amt in (("1", ded), ("2", coins)) if amt != 0]
                if pr:
                    b.add("CAS", "PR", *[x for code, amt in pr for x in (code, money(amt), "")][:-1])
                if contractual != 0:
                    b.add("CAS", "CO", "45", money(contractual))
                stats["lines"] += 1
            stats["claims"] += 1
            stats["charge"] += charge
        b.add("SE", str(len(b.segments) - st_index + 1), st_ctrl)
        stats["payments"] += 1
        stats["paid"] += payment
    b.add("GE", str(stats["payments"]), str(isa_control))
    b.add("IEA", "1", ctrl)
    stats["segments"] = len(b.segments)
    return SEG.join(b.segments) + SEG + "\n", stats


def validate(text, expect_claims, expect_paid):
    """Re-read the 835 and enforce X12 balancing: line, claim and payment level."""
    errors, segs = [], [s.strip("\n") for s in text.strip().rstrip(SEG).split(SEG)]
    claims, paid_total = 0, Decimal("0")
    bpr = clp = line = None
    def close_line():
        if line and line[0] != line[1] + line[2]:
            errors.append(f"line {line[3]}: charge {line[0]} != paid {line[1]} + adjustments {line[2]}")
    def close_claim():
        if clp and (clp[1] != clp[3] or clp[2] != clp[4]):
            errors.append(f"claim {clp[0]}: CLP03/04 {clp[1]}/{clp[2]} != lines {clp[3]}/{clp[4]}")
    def close_payment():
        if bpr and bpr[0] != bpr[1]:
            errors.append(f"BPR02 {bpr[0]} != sum CLP04 {bpr[1]}")
    st = None
    for i, s in enumerate(segs):
        e = s.split(ELEM)
        if e[0] == "ST":
            st = i
        elif e[0] == "SE":
            close_line(); close_claim(); close_payment()
            if int(e[1]) != i - st + 1:
                errors.append("SE01 segment count is wrong")
            bpr = clp = line = None
        elif e[0] == "BPR":
            bpr = [Decimal(e[2]), Decimal("0")]
        elif e[0] == "CLP":
            close_line(); close_claim(); line = None
            clp = [e[1], Decimal(e[3]), Decimal(e[4]), Decimal("0"), Decimal("0")]
            bpr[1] += Decimal(e[4]); claims += 1; paid_total += Decimal(e[4])
        elif e[0] == "SVC":
            close_line()
            line = [Decimal(e[2]), Decimal(e[3]), Decimal("0"), e[1]]
            clp[3] += Decimal(e[2]); clp[4] += Decimal(e[3])
        elif e[0] == "CAS":
            for k in range(3, len(e), 3):
                if e[k]:
                    line[2] += Decimal(e[k])
    if claims != expect_claims:
        errors.append(f"claims {claims} != expected {expect_claims}")
    if paid_total != expect_paid:
        errors.append(f"paid {paid_total} != expected {expect_paid}")
    return errors


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--from", dest="from_", default="2017-01")
    ap.add_argument("--to", default="2099-12")
    args = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s", datefmt="%H:%M:%S")
    conn = get_connection()
    conn.autocommit = True
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute(MANIFEST_DDL)
    cur.execute(CLAIMS_SQL, {"from": args.from_, "to": args.to})
    claims = cur.fetchall()
    if not claims:
        log.warning("No received 837P claims in this window: load 837s and run dbt build first.")
        return 0
    cur.execute(LINES_SQL, {"ids": [c["claim_id"] for c in claims]})
    lines = defaultdict(list)
    for l in cur.fetchall():
        lines[l["claim_id"]].append(l)
    cur.execute(ORGS_SQL)
    orgs = {o["ident"]: o for o in cur.fetchall() if o["ident"]}
    cur.execute("SELECT coalesce(max(isa_control), 0) AS last FROM audit.edi_file_manifest")
    isa_control = cur.fetchone()["last"]
    groups = defaultdict(list)
    for c in claims:
        groups[(c["payer_name"], c["claim_thru_date"].strftime("%Y-%m"), c["usage_indicator"])].append(c)
    run_id, now = uuid.uuid4(), datetime.now()
    totals = {"files": 0, "payments": 0, "claims": 0, "paid": Decimal("0")}
    for (payer, month, usage), group in sorted(groups.items()):
        isa_control += 1
        text, stats = build_file(payer, month, group, lines, orgs, usage, isa_control, now)
        errors = validate(text, len(group), stats["paid"])
        if errors:
            log.error("FAIL %s %s: %s", payer, month, "; ".join(errors[:5]))
            return 1
        safe = re.sub(r"[^A-Za-z0-9]+", "_", payer).strip("_").upper()
        path = OUT_ROOT / safe / f"835_{safe}_{month.replace('-', '')}_{usage}.x12"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="ascii")
        cur.execute("""INSERT INTO audit.edi_file_manifest (file_id, run_id, transaction_set, usage_indicator,
                         payer_name, service_month, file_path, isa_control, claim_count, line_count, total_charge,
                         segment_count, file_sha256, validated)
                       VALUES (%s,%s,'835',%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,true)""",
                    (str(uuid.uuid4()), str(run_id), usage, payer, month, str(path), isa_control, stats["claims"],
                     stats["lines"], stats["paid"], stats["segments"], hashlib.sha256(text.encode()).hexdigest()))
        totals["files"] += 1; totals["payments"] += stats["payments"]
        totals["claims"] += stats["claims"]; totals["paid"] += stats["paid"]
    if totals["claims"] != len(claims):
        log.error("Run reconciliation failed: %s remitted vs %s received", totals["claims"], len(claims))
        return 1
    print(f"\nRun {run_id}: {totals['files']} files, {totals['payments']} payments, {totals['claims']:,} claims, "
          f"${totals['paid']:,.2f} paid - all files balanced, validated and reconciled")
    return 0


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).parent))
    sys.exit(main())
