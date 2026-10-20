-- One row per valid diagnosis code on a claim (unpivoted, F8), with ICD-10 conversion.
-- STTM: silver.claim_diagnosis. Conversion rules: docs/mapping/icd9_to_icd10_conversion_spec.md
-- Conversion is looked up from ref.icd9_dx_conversion (one decision per distinct code),
-- so every claim with the same ICD-9 code gets the same, reviewable ICD-10 result.
select
    v.source_system,
    v.claim_id,
    v.claim_type,
    v.segment,
    v.position                                   as dx_position,
    case
        when v.position = 0                      then 'ADMITTING'
        when v.segment = 1 and v.position = 1    then 'PRINCIPAL'
        else 'SECONDARY'
    end                                          as dx_role,
    v.raw_value                                  as icd9_code,
    (c.gem_match_type <> 'NOT_IN_GEM')           as icd9_in_reference,
    c.icd10_code,
    c.gem_match_type,
    c.decided_by                                 as conversion_decided_by,
    c.target_billable                            as icd10_billable,
    v.source_table,
    v._source_row_num
from {{ ref('int_claim_code_value') }} v
left join {{ source('ref', 'icd9_dx_conversion') }} c
  on c.icd9_code = v.raw_value
where v.code_system = 'ICD9-DX'
  and v.reason_code is null
