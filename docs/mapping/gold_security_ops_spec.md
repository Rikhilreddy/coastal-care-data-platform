# GOLD, SEC, ORCH, CI, DASH: analytics layer and operations

## GOLD: star schema (schema `gold`, de-identified)
| Model | Grain | Notes |
|---|---|---|
| `dim_member` | member | Birth year, age band, sex, state. No name, SSN, address or exact DOB |
| `dim_date` | day | 2007–2030 |
| `fct_claim` | claim | Net of adjustments (recoupments are negative rows); line of business from payer (macro `line_of_business`) |
| `fct_member_coverage_year` | member × year | Member months = months with Part A, Part B or HMO coverage (DE-SynPUF). Synthea members get enrollment from the 834 |
| `mart_pmpm` | source × LOB × year × claim type | PMPM = net paid / member months. Paid with no enrollment that year is reported separately, never dropped |
| `fct_inpatient_stay` | stay | Overlapping or same-day claims (transfers, interim bills) merged with a gaps-and-islands pattern |
| `mart_readmission_30d`, `mart_readmission_rate` | stay; source × LOB × year | All-cause 30-day readmission. Index stay: discharged alive with 30 days of follow-up in the data. **Not yet applied:** CMS planned-readmission algorithm |
| `mart_charge_outlier` | billed line | Above p99 for the CPT/HCPCS code **and** more than 3× the median, with at least 20 lines of history (H32) |
| `mart_edi_readiness` | LOB × payer × month × status | READY or the first failing pre-submission edit |
| `mart_data_quality` | metric | MPI precision, recall and review count, quarantine counts, outliers, 837 readiness: aggregates only |

**Tests**
| Test | Proves |
|---|---|
| `assert_gold_paid_reconciles` | Gold net paid = silver net paid, per source and year; the PMPM mart adds back to the total |
| `assert_member_months_valid` | 0 to 12 months per member-year |
| `assert_stays_do_not_overlap` | After merging, stays never overlap |
| Unit test `transfer_claims_merge_into_one_stay` | A same-day transfer is one stay; a stay 10 days later is a new stay; adjustments are excluded |
| `relationships` | Every claim has a member and a date in the dimensions |

## SEC: HIPAA access control (minimum necessary)
| Role | Can read | Cannot read |
|---|---|---|
| `cc_analyst` | gold | everything else |
| `cc_engineer` | staging, silver, quarantine, edi, hl7, ref, gold, `silver.member_identity_masked` | bronze, identity tables, raw X12 and HL7, MPI, MPI answer key |
| `cc_steward` | all of the above plus identities and the MPI | |
| `cc_auditor` | audit (load manifests, approvals) | business data |

- `security/10_roles_and_access.sql` creates the roles and schema access. Run it once, before `dbt build`.
- Table grants are dbt `+grants` in `dbt_project.yml`, re-applied on every build, because a rebuilt table loses manual grants (a real production gotcha).
- Models that carry direct identifiers override this to `cc_steward` only: `member_identity`, `stg_fhir__patient`, `hl7_adt_event`, `edi_inbound_837p_claim`, and the raw X12 segment views.
- `security/check_access.sh` proves 18 allow/deny rules with `SET ROLE`. It runs in CI.
- The dashboard runs `SET ROLE cc_analyst`, so it can only ever show gold.

## ORCH: Apache Airflow 3 DAG (`orchestration/dags/coastal_care_daily.py`)
The DAG chains: bronze loads (FHIR, X12, HL7, in parallel) → `dbt build` → HIPAA access check → 837P → round-trip load → dbt (edi) → 835 → load → final `dbt build`.

| Setting | Why |
|---|---|
| `max_active_runs=1` | Two runs never write bronze at the same time |
| Retries | Safe because every loader is idempotent |
| Claim window | 45 days back, or `from_month` in the run conf for a backfill |

Tested locally with `airflow dags test`: all 11 tasks succeeded.

## CI: GitHub Actions (`.github/workflows/ci.yml` → `ci/run_ci.sh`)
Each push or pull request starts a Postgres 16 service container and restores the synthetic fixture (`ci/fixtures/coastal_care_fixture.dump`: bronze, ref and audit schema, no real data). It then runs:

1. Roles
2. `dbt build` (159 nodes)
3. Access proof
4. 837P out → pyx12 → in
5. 835 out → pyx12 → in
6. ADT out → python-hl7 → in, twice (idempotency)
7. `dbt build` again

Any failure turns the PR red. The full run takes about 40 s locally.

## DASH: Streamlit (`dashboard/app.py`)
- **Tiles:** members, claims, net paid, readmission rate.
- **Charts:** PMPM by line of business, net paid by claim type, readmission rate by year, 837P readiness by edit.
- **Tables:** the data-quality scorecard and data tables for accessibility.
- Each line of business keeps a fixed colour; every chart has hover tooltips.
