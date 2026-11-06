# EDI-1: Outbound X12 837P Specification

**Purpose:** turn Synthea FHIR professional claims into HIPAA X12 5010 837P files (`005010X222A1`), the way a provider network's clearinghouse submits claims to payers. EDI-2 parses the files back in as inbound claims.
**Findings that drive this design:** `docs/profiling/edi_findings.md` (H19–H31)

## Pipeline

```
silver.claim_header (FHIR, non-RX)
   │
   ├─ staging.stg_fhir__eob_line      priced EOB lines (date of service, place of service, NPI, charge)
   ├─ edi.edi_claim_line              each line → SERVICE (CPT/HCPCS) | BUNDLED | UNMAPPED
   └─ edi.edi_claim_readiness         pre-submission edits → READY or one reject reason
            │
            └─ edi/generate_837p.py   READY PROF claims → one 837P per payer per month
                                      → validated, reconciled, logged in audit.edi_file_manifest
```

## Pre-submission edits (first failing edit wins)

| Order | Reject reason | Rule | Finding |
|---|---|---|---|
| 1 | `SELF_PAY` | Payer is NO_INSURANCE: patient statement, not an 837 | H30 |
| 2 | `INSTITUTIONAL_837I_BACKLOG` | IP/OP facility claims need an 837I (revenue codes, bill type): later ticket | H8 |
| 3 | `DENTAL_OUT_OF_SCOPE` | Dental claims need CDT codes on an 837D; CDT is ADA-licensed | H29 |
| 4 | `UNMAPPED_SERVICE_CODE` | A service line has no crosswalk row | H22 |
| 5 | `NO_BILLABLE_SERVICE` | Only supplies or non-service items | H25 |
| 6 | `NO_DIAGNOSIS` | No codable diagnosis and no visit-reason rule | H21, H28 |

**Reconciliation (dbt tests):** non-RX FHIR claims = READY + REJECTED (count and billed dollars); for every READY claim, Σ 837 line charges = billed amount.

## Service lines

| Category | Behaviour |
|---|---|
| SERVICE | Own SV1 line with the crosswalk's CPT / HCPCS Level II code |
| E_M_BY_AGE | Preventive visit, CPT 99391–99397 by age on the date of service |
| BUNDLED | No line of its own; its charge is added to the claim's first SERVICE line (claim total unchanged) |
| Not in crosswalk, non-service SNOMED tag (physical object, finding, ...) | BUNDLED by rule |
| Not in crosswalk, service tag / LOINC / CVX | UNMAPPED → claim rejected |

Screening **instruments** (PHQ-2, GAD-7, AUDIT-C, Morse) are bundled when the matching SNOMED screening **procedure** on the same visit already bills the service, so a screening is billed once.

## Diagnoses

1. Claim diagnoses converted through the SNOMED → ICD-10-CM crosswalk (CONV-4), principal first, deduplicated, at most 12 (`HI`, ABK then ABF).
2. If none are codable, the **visit-reason rule** (`encounter_reason_dx`) applies to visit types with a standard reason code: check-up / general exam (Z00.00 adult, Z00.129 child), well child (Z00.129), vaccine (Z23), prenatal (Z34.90), postpartum (Z39.2).
3. A problem visit with no coded problem is a genuine reject (`NO_DIAGNOSIS`).

## Governance and usage indicator (ISA15)

| | Test files (`--usage T`) | Production files (`--usage P`) |
|---|---|---|
| Mappings allowed | APPROVED and PROPOSED | APPROVED only (service lines, diagnoses, visit-reason rule) |
| ISA15 | `T` | `P` |

All three crosswalks (`snomed_icd10_crosswalk`, `service_line_crosswalk`, `encounter_reason_dx`) are dbt seeds with governance tests: valid code formats, HCPCS Level II present in the CMS file, ICD-10-CM targets billable in FY2027, approvals signed.

## Synthetic identifiers (never real)

| Element | Source |
|---|---|
| Billing provider NPI (2010AA NM109) | Derived from the Synthea organization id: `1` + 8 hash digits + valid Luhn check digit (prefix 80840). Organizations carry no NPI (H19) |
| Billing TIN (REF*EI) | Deterministic 9-digit value starting with 9 |
| Payer ID, submitter ETIN | Deterministic synthetic values |
| Rendering NPI (2310B) | From the EOB care team, **sent as received** (H27). NPIs failing the check digit are counted as a data-quality finding, not dropped |

## Validation

Each file is re-read before it is accepted: ISA length 105, IEA02 = ISA13, SE01 segment count, HL parent links, procedure and diagnosis composite formats, CLM02 = Σ SV102 per claim, and file and run totals equal the READY claims. Independent check: `x12valid <file>` (pyx12, open source) validates against the 005010X222A1 implementation guide.

## Licensing

CPT codes are AMA-licensed: used as code values only; no CPT descriptions are stored. HCPCS Level II, ICD-10-CM and the CVX → CPT vaccine mapping (CDC) are free. X12 implementation guides are not used; the layout follows free CMS companion guides.

## EDI-2: inbound 837P (payer side) and round-trip reconciliation

```
.x12 files ──► edi/load_bronze_x12.py ──► bronze.x12_segment (one row per segment, as received)
                                              │
                staging.stg_x12__837p_segment  loop context from position (window running counts)
                                              │
                edi.edi_inbound_837p_claim / edi.edi_inbound_837p_line
                                              │
                round-trip tests vs edi.edi_claim_readiness / edi.edi_claim_line
```

- **Bronze stores segments, not parsed claims.** Delimiters are read from each file's ISA header, so any trading partner's files parse. Loader checks: ISA/IEA envelope, SE01 count per transaction, segments and Σ CLM02 in file = in database; idempotent by SHA-256.
- **Loops from position.** `billing_seq` (HL…20), `subscriber_seq` (HL…22), `claim_seq` (CLM) and `line_seq` (LX) are running counts over the file; every segment inherits the nearest loop opener above it.
- **Round trip.** `assert_837p_roundtrip_claims` compares total, payer, member, rendering NPI and diagnoses; `assert_837p_roundtrip_lines` compares line count, order, code, charge and date. A file altered in transit, a parser bug, or a **stale file** (generated before a crosswalk change) fails the build.
- **Not unioned into `silver.claim_header`.** The 837s carry the same claims as the FHIR source; adding them would double-count in gold. EDI is a channel, validated here; FHIR remains the system of record for these claims.

**Lesson recorded:** `dbt test` checks tables as last built. After new files land, run `dbt build` (rebuild, then test), or a tampered file passes.

## EDI-3: outbound 835 remittance (payer → provider)

The 835 is the payer's answer to the 837: what it paid on each claim and service line, and why the rest was not paid.

| Step | What | Where |
|---|---|---|
| 1 | Read the claims the payer **received** (inbound 837P) | `edi.edi_inbound_837p_claim` / `_line` |
| 2 | Take allowed, paid, deductible, coinsurance per line from the FHIR EOB | `stg_fhir__eob_line` (macro `bb_adjudication`) |
| 3 | Bundle EOB lines exactly like the 837 lines (bundled amounts move to the anchor line) | `edi_claim_line` |
| 4 | Write one file per payer per month, one ST/BPR payment per payee | `edi/generate_835.py` |
| 5 | Load the 835s back into bronze and parse them | `load_bronze_x12.py`, `stg_x12__835_segment`, `edi_inbound_835_claim` / `_line` |

**Balancing (checked in Python before writing, then again in dbt):**

| Level | Rule |
|---|---|
| Line | SVC02 charge = SVC03 paid + CAS (PR-1 deductible, PR-2 coinsurance, CO-45 contractual remainder) |
| Claim | CLP03 = Σ SVC02, CLP04 = Σ SVC03 |
| Payment | BPR02 = Σ CLP04 per payee |

Implementation rules (from pyx12): ST03 is "Not Used" in 835 5010, and CLP06 does not allow `CI`; `REMIT_FILING_INDICATOR` maps to MB, MC, or default `12`.

| dbt test | Proves |
|---|---|
| `assert_835_balances` | Every line, claim and payment balances |
| `assert_835_completes_837` | Every received 837 claim has exactly one 835 claim |
| `assert_835_paid_matches_eob` | 835 paid = EOB paid, within 1 cent per line (H17 float payments) |
