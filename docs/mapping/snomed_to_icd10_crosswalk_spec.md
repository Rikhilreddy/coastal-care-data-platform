# SNOMED CT → ICD-10-CM Crosswalk Specification (CONV-4, v1)

**Applies to:** Synthea FHIR `Condition` resources (259 distinct SNOMED CT codes, 46,488 conditions)
**Artifact:** `dbt/seeds/snomed_icd10_crosswalk.csv` → `ref.snomed_icd10_crosswalk` (`map_source = COASTAL_CROSSWALK_V1`)
**Why not the NLM map:** the NLM SNOMED CT → ICD-10-CM map requires a UMLS licence; this project uses only free/open data (docs/decisions.md). The crosswalk is internal, governed, and replaceable by the NLM map later without changing silver.

## Categories

| Category | Meaning | ICD-10-CM target | Share of conditions |
|---|---|---|---|
| DIAGNOSIS | Disorder, symptom or injury | Billable code (A00–Y99 excluding Z) | 39.8% |
| SDOH | Social determinant / psychosocial finding | Z55–Z65, Z72–Z73, Z91.41- | 20.7% |
| STATUS_HISTORY | History, status, encounter context | Other Z codes, I25.2 | 2.9% |
| NOT_CODABLE | No ICD-10-CM meaning (employment, education, "medication review due", uncertain "suspected" diagnoses) | none | 36.7% |

## Coding conventions

1. **Billable codes only.** Every target must be a billable FY2027 code (it can go on an 837).
2. **Initial encounter.** Injuries use 7th character `A`.
3. **Unspecified side and site** when SNOMED gives none; never guessed.
4. **No overcoding.** Screening findings are not coded as disorders (e.g. "unhealthy alcohol drinking behavior" → Z72.89, not F10.-), because overcoding inflates HCC risk scores.
5. **Uncertain diagnoses are not coded** ("suspected lung cancer"), following ICD-10-CM outpatient guideline IV.H.
6. **Type 2 diabetes** is assumed for diabetic complications (Synthea's diabetes module is type 2).

## Sensitive codes

32 codes are flagged `sensitive = true`: behavioral health, substance use (42 CFR Part 2), reproductive health, abuse and violence, criminal record, and immigration or migration status. Gold views mask them beyond the default HIPAA minimum-necessary rules.

## Governance (enforced by dbt tests on every build)

| Test | Rule |
|---|---|
| `assert_crosswalk_targets_valid` | Every target exists in FY2027 and is billable; NOT_CODABLE rows have no target |
| `assert_crosswalk_approvals_signed` | APPROVED rows name a reviewer and a review date |
| `assert_crosswalk_covers_all_conditions` | Every SNOMED condition code in bronze has a crosswalk row; a new code fails the build until mapped |
| `unique` / `accepted_values` | One row per SNOMED code; valid category and status |

Only `APPROVED` rows are used in silver. Review order: `review_priority = HIGH` first (≥200 conditions, HCC-relevant families, or sensitive).

## How silver uses the crosswalk (CONV-4b)

`silver.claim_diagnosis` now holds diagnoses from every source in one shape: `source_code_system` + `source_code` keep the original (ICD9CM or SNOMEDCT), `icd10_code` is the common language, and `conversion_method` says how it was decided.

| FHIR `conversion_method` | Meaning | `icd10_code` |
|---|---|---|
| CROSSWALK | APPROVED crosswalk row with a target | Set |
| NOT_CODABLE | APPROVED as having no ICD-10-CM meaning | NULL |
| PENDING_REVIEW | Crosswalk row still PROPOSED | NULL (never guessed) |
| REJECTED | Reviewer rejected the proposal | NULL |
| NOT_IN_CROSSWALK | Code missing from the crosswalk (the coverage test fails the build first) | NULL |

A `Claim.diagnosis` entry whose Condition is not in the bundle goes to `quarantine.code_exception` with reason `UNRESOLVED_REFERENCE`.

**Tests:** `assert_fhir_diagnoses_reconcile_to_bronze` (every bronze diagnosis entry lands exactly once, in silver or quarantine) and `assert_fhir_icd10_only_from_approved_crosswalk` (no ICD-10 code without an approval). If any crosswalk governance test fails, dbt skips `claim_diagnosis`, so an invalid crosswalk can never reach silver.

**Change from v1 of `silver.claim_diagnosis`:** `icd9_code` → `source_code` (+ `source_code_system`), `gem_match_type` → `conversion_method`, `icd9_in_reference` removed (derivable from `conversion_method`), `is_sensitive` added.

**Quality report:** `sql/conversion/05_fhir_dx_conversion_report.sql` (C1–C7); section C3 is the SME worklist.
