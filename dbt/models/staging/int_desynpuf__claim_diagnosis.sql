-- DE-SynPUF part of silver.claim_diagnosis: valid ICD-9-CM diagnoses with the CONV-2 ICD-10 decision.
-- Conversion rules: docs/mapping/icd9_to_icd10_conversion_spec.md
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
    'ICD9CM'::text                               as source_code_system,
    v.raw_value                                  as source_code,
    c.icd10_code,
    c.gem_match_type                             as conversion_method,
    c.decided_by                                 as conversion_decided_by,
    c.target_billable                            as icd10_billable,
    null::boolean                                as is_sensitive,      -- not assessed for ICD-9 (backlog)
    v.source_table,
    v._source_row_num
from {{ ref('int_claim_code_value') }} v
left join {{ source('ref', 'icd9_dx_conversion') }} c
  on c.icd9_code = v.raw_value
where v.code_system = 'ICD9-DX'
  and v.reason_code is null
