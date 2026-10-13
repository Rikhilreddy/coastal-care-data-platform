# ICD-9-CM → ICD-10-CM Diagnosis Conversion Specification (v1)

**Applies to:** `silver.claim_diagnosis` (legacy DE-SynPUF claims, 2008–2010)
**Reference data:** CMS 2018 diagnosis GEMs (`2018_I9gem.txt`, forward; `2018_I10gem.txt`, backward), ICD-10-CM FY2027 order file
**Principle:** every conversion is deterministic, reproducible, and labeled with how confident it is. Nothing is guessed silently.

## 1. Why conversion is needed

The acquired plan's history is coded in ICD-9-CM. Every modern process at Coastal Care (risk adjustment, quality measures, analytics) runs on ICD-10-CM. Without conversion, three years of history cannot be trended or used for CMS-HCC risk scoring.

## 2. GEM structure

Each row of the forward GEM (`2018_I9gem.txt`) has: source ICD-9 code, target ICD-10 code, and a 5-character flag string:

| Position | Flag | Meaning when `1` |
|---|---|---|
| 1 | Approximate | Target is not an exact equivalent |
| 2 | No Map | No ICD-10 equivalent exists (target = `NoDx`) |
| 3 | Combination | The ICD-9 code requires **more than one** ICD-10 code together |
| 4 | Scenario | Which alternative combination (1–9) this row belongs to |
| 5 | Choice list | Which slot within the combination (1–9) this row fills |

Codes are stored without decimal points in both GEMs and claims (e.g., `25000`), so no reformatting is needed to join.

## 3. Conversion rules

Applied in this order for each distinct ICD-9 code found in claims:

| Rule | Condition | Action | `gem_match_type` |
|---|---|---|---|
| R1 | ICD-9 code not present in GEM source list | No conversion; log `CONVERSION_NOT_IN_GEM` in `quarantine.code_exception` (claim retained) | `NOT_IN_GEM` |
| R2 | No Map flag = 1 | `icd10_code` = null; log `CONVERSION_NO_MAP` | `NO_MAP` |
| R3 | Exactly one target, approximate = 0, combination = 0 | Use that target | `EXACT` |
| R4 | Exactly one target, approximate = 1, combination = 0 | Use that target | `APPROXIMATE` |
| R5 | Multiple alternative targets, combination = 0 | Select one using the tie-break below | `APPROXIMATE_MULTI` |
| R6 | Combination = 1 | Use **scenario 1**; within each choice list, select one target using the tie-break. The first choice list's code becomes `icd10_code`; all codes for the scenario are written to `silver.dx_conversion_detail` | `COMBINATION` |

### Tie-break for multiple candidates (R5, R6)

Deterministic, applied in order until one candidate remains:

1. **Reciprocal match:** prefer candidates whose backward GEM (`2018_I10gem.txt`) maps back to the same ICD-9 code. This is the CMS-recommended way to use both GEM directions.
2. **Valid today:** prefer candidates that are valid codes in ICD-10-CM FY2027.
3. **Billable:** prefer candidates flagged billable (valid for HIPAA transactions) in the FY2027 order file.
4. **Unspecified preference:** prefer the candidate whose description contains "unspecified", because a historical claim cannot prove the extra specificity ICD-10 demands. Choosing a more specific code would invent clinical detail.
5. **Lowest code:** alphabetical order, so the result is always reproducible.

`candidate_count` and the deciding tie-break step are recorded for every conversion.

## 4. Target validity (FY2027)

GEMs were last published for FY2018. Some 2018 targets have since been expanded or deleted.

| Check | Result | Action |
|---|---|---|
| Target exists in FY2027 order file and is billable | Valid | No flag |
| Target exists but is a non-billable header | `target_billable = false` | Flag; kept for analytics, would be rejected on a HIPAA 837 |
| Target not in FY2027 file | `target_valid_fy2027 = false` | Flag; known limitation, resolvable later with the annual ICD-10-CM conversion tables |

## 5. Output

| Table | Grain | Key columns |
|---|---|---|
| `ref.gem_icd9_to_icd10` | One row per GEM row (forward) | `icd9_code, icd10_code, approximate, no_map, combination, scenario, choice_list` |
| `ref.gem_icd10_to_icd9` | One row per GEM row (backward) | Same layout, reversed |
| `ref.icd10cm` | One row per FY2027 code | `icd10_code, is_billable, short_desc, long_desc` |
| `ref.icd9_dx_conversion` | One row per distinct ICD-9 code in claims | `icd9_code, icd10_code, gem_match_type, candidate_count, decided_by, target_valid_fy2027, target_billable` |
| `silver.dx_conversion_detail` | One row per ICD-10 code produced (combination codes included) | `icd9_code, scenario, choice_list, icd10_code` |
| `silver.claim_diagnosis` | Unchanged grain; adds `icd10_code`, `gem_match_type` | Joined from `ref.icd9_dx_conversion` |

Converting once per **distinct** code (thousands) instead of per claim row (millions) keeps the logic auditable: every decision can be reviewed in one table.

## 6. Quality metrics (reported after every run)

- Share of distinct ICD-9 codes, and of claim diagnosis rows, by `gem_match_type`
- Share of **principal** diagnoses converted `EXACT` or `APPROXIMATE`
- Paid dollars on claims whose principal diagnosis is `NO_MAP` or `NOT_IN_GEM`
- Count of targets not valid or not billable in FY2027

These go into the reconciliation report so conversion quality is visible, not assumed.

## 7. Known limitations

- GEMs are not a clinical coding tool; they translate code meaning, not documentation. Converted codes are suitable for analytics, trending, and risk-adjustment modeling, **not** for resubmitting claims.
- Combination conversions use scenario 1 only.
- The FY2018 → FY2027 code drift is flagged, not corrected, in v1.
