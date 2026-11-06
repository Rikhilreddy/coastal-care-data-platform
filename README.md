# Coastal Care Data Platform

![CI](https://github.com/Rikhilreddy/coastal-care-data-platform/actions/workflows/ci.yml/badge.svg)

An end-to-end **healthcare data engineering** platform: claims, clinical and enrollment data move from raw files to an analytics star schema. On the way, the platform converts code sets, exchanges HIPAA X12 EDI and HL7 v2 messages, matches patients across systems, and enforces HIPAA access rules. Every step is reconciled and tested.

Everything is **free and open source**. All data is **synthetic** (CMS DE-SynPUF, Synthea) and is still handled as if it were PHI.

## What it demonstrates
| Area | What is built | Proof |
|---|---|---|
| **ETL / ELT** | Idempotent bronze loaders (SHA-256 manifest, one transaction per file, reconcile before commit) → dbt silver → gold | `audit.load_manifest`; reconciliation tests on members, claims, codes and dollars |
| **Medallion architecture** | bronze → staging → silver (+ quarantine) → gold on PostgreSQL 16 | Nothing is dropped silently: rejects go to `quarantine` with a reason |
| **Source-to-target mapping** | STTM documents for DE-SynPUF, FHIR R4, X12 and HL7 | `docs/mapping/` |
| **Data conversion** | ICD-9-CM → ICD-10-CM (CMS GEMs plus governed overrides); SNOMED CT → ICD-10-CM crosswalk with signed approvals (PROPOSED / APPROVED / REJECTED) | Governance tests: approvals signed, targets billable, every condition covered |
| **FHIR R4** | Synthea bundles stored as JSONB; JSONPath selects elements by meaning, not position | FHIR reconciliation tests (claims, members, diagnoses, cents) |
| **X12 EDI 837P** | Pre-submission edits, service-line crosswalk, bundling rules, envelopes, Luhn-valid synthetic NPIs | Every file validated by **pyx12**; round-trip test (837 out = 837 in) |
| **X12 EDI 835** | Remittance with CAS PR-1 / PR-2 / CO-45, balancing at line, claim and payment level | `assert_835_balances`; 835 paid = FHIR EOB paid within 1 cent |
| **X12 EDI 834** | Enrollment from Synthea coverage history; payer member IDs matched to members by the MPI; feeds member months | pyx12; round-trip test (history = enrollment received, dates included) |
| **HL7 v2.5.1** | ADT A01/A03 feed with facility MRNs; parser uses the MSH separators and field positions | Parsed by **python-hl7**; every inpatient stay has exactly one A01 and one A03 |
| **MPI** | Blocking, weighted scoring (pg_trgm), AUTO_LINK / REVIEW / NO_MATCH on two feeds (HL7 ADT, X12 834), measured against a seeded answer key | **0 false links** on real-size data (377 of 379 ADT identities auto-linked, 2 to review); with all SSNs removed, still 0 false links |
| **HCPCS / CPT, ICD-10** | CMS HCPCS and ICD-10-CM reference sets; no AMA CPT descriptions (licensed) | `code_exception` quarantine for unresolved codes |
| **HIPAA** | Roles (analyst, engineer, steward, auditor), masked identity view, de-identified gold, dbt-managed grants | `security/check_access.sh`: 18 allow/deny rules, run in CI |
| **Analytics** | Star schema, PMPM by line of business (member months from DE-SynPUF and the 834), 30-day readmissions, charge outliers | Gold paid = silver paid (test); 15.1% Medicare readmission rate (2008), in line with national rates |
| **Orchestration** | Apache Airflow 3 DAG | All 14 tasks succeed in `airflow dags test` |
| **CI/CD** | GitHub Actions: Postgres service container, synthetic fixture, full pipeline | About 160 dbt checks plus the EDI and HL7 round trips on every PR |
| **Dashboard** | Streamlit, read-only role `cc_analyst` | Cannot read PHI schemas by construction |

## Architecture
```
 Synthea FHIR R4 ─┐                                  ┌─> 837P out ──pyx12──> 837P in ─┐
 CMS DE-SynPUF ───┼─> bronze ─> staging ─> silver ───┤                                 ├─> 835 out ─pyx12─> 835 in
 Synthea coverage CSV ─> bronze ─> 834 out ─pyx12─> 834 in ─> MPI ─> member months ─> PMPM
 CMS ICD-10/HCPCS ┘   (raw,      (typed     (members, │                                 │
 HL7 ADT ─────────────idempotent) views)    claims,  ├─> HL7 ADT ─> hl7 ─> MPI ─────────┘
                                            codes)   └─> gold (star schema, PMPM, readmissions) ─> Streamlit
                       quarantine <── rejected rows and codes, with reasons
                       audit <── load manifests, approvals, MPI answer key
```

## Quick start
```bash
python -m venv .venv && source .venv/bin/activate
pip install -r ci/requirements-ci.txt streamlit
cp .env.example .env                       # PG_HOST, PG_DB, PG_USER, PG_PASSWORD (never committed)
psql -d coastal_care -f security/10_roles_and_access.sql
cd dbt && dbt build && cd ..
streamlit run dashboard/app.py
```
To prove everything on a throwaway database, as CI does: `PG_DB=coastal_care_ci ./ci/run_ci.sh`

## Repository layout
| Path | Contents |
|---|---|
| `ingestion/` | Bronze loaders (DE-SynPUF, FHIR, Synthea enrollment CSV, reference code sets) |
| `edi/` | 837P, 835 and 834 generators, X12 bronze loader |
| `hl7/` | ADT generator, HL7 bronze loader |
| `dbt/` | Models (staging, silver, quarantine, edi, hl7, mpi, gold), macros, seeds (crosswalks), tests |
| `security/` | Roles and access proof |
| `orchestration/` | Airflow DAG |
| `dashboard/` | Streamlit app |
| `ci/` | CI script, synthetic fixture, pinned requirements |
| `docs/` | Mapping specs (STTM), profiling findings (H1–H37), decisions |

## Data rules
- `data/` and `.env` are never committed. Credentials come only from environment variables.
- Synthetic data is treated as PHI: identities live in one restricted table, and analytics sees de-identified gold only.
- Licensed content is excluded: no CPT descriptions (AMA), no CDT (ADA), no UMLS.

## Known limitations and backlog
- 837I (institutional) and dental 837D are out of scope; held by pre-submission edits.
- Production (ISA15=P) files need SME approval of the service-line crosswalk; test files use PROPOSED mappings.
- The readmission measure does not yet apply the CMS planned-readmission algorithm.
- 834 dependents are sent as subscribers and secondary coverage (COB) is not sent (H38–H40).
- CMS-HCC risk scores: next increment (needs the free CMS ICD-10 → HCC mapping file).
- Synthea rendering NPIs fail the NPI check digit; they are sent as received and reported as a data-quality finding.
