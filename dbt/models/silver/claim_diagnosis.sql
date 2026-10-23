-- One row per diagnosis on a claim, every source, with its ICD-10-CM conversion.
--   DE-SynPUF: ICD-9-CM via CMS GEMs + SME overrides (CONV-2)
--   FHIR:      SNOMED CT via the governed crosswalk, APPROVED rows only (CONV-4)
-- source_code_system + source_code keep the original code; icd10_code is the common language.
select {{ claim_diagnosis_columns() }} from {{ ref('int_desynpuf__claim_diagnosis') }}
union all
select {{ claim_diagnosis_columns() }} from {{ ref('int_fhir__claim_diagnosis') }} where not is_unresolved
