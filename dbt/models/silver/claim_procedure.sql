-- One row per valid procedure code on a claim: ICD-9-CM procedures (inpatient) and
-- HCPCS/CPT (both claim types). STTM: silver.claim_procedure
-- HCPCS Level II is checked against the CMS file, but only FLAGGED, never rejected:
-- the file is current (2026) and 2008-2010 codes may since have been deleted (validation
-- design constraint 1). CPT (Level I) is AMA-licensed: format-checked only.
select
    v.source_system,
    v.claim_id,
    v.claim_type,
    v.segment,
    v.code_system,
    v.position,
    v.raw_value                                       as procedure_code,
    case
        when v.code_system <> 'HCPCS'                 then null
        when v.raw_value ~ '^[A-Z]'                   then 'II'
        else 'I'
    end                                               as hcpcs_level,
    case
        when v.code_system = 'HCPCS' and v.raw_value ~ '^[A-Z]'
        then (h.hcpcs_code is not null)
    end                                               as in_current_reference,
    v.source_table,
    v._source_row_num
from {{ ref('int_claim_code_value') }} v
left join {{ source('ref', 'hcpcs') }} h
  on h.hcpcs_code = v.raw_value
where v.code_system in ('ICD9-PROC', 'HCPCS')
  and v.reason_code is null
