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
