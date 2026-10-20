{{ config(materialized='table') }}
-- One row per non-null code value on a non-orphan claim segment (wide -> long, F8),
-- with the validation result. Classify ONCE here, then split:
--   reason_code IS NULL     -> silver.claim_diagnosis / silver.claim_procedure
--   reason_code IS NOT NULL -> quarantine.code_exception
-- So every value lands in exactly one place, which the reconciliation test proves.
-- Not unpivoted: outpatient ICD-9 procedure columns (F6, ~100% empty; OP uses HCPCS).

with seg as (
    select * from {{ ref('stg_desynpuf__claim_segment') }}
    where not is_orphan_segment            -- orphan segments are quarantined whole (F12)
),
unpivoted as (
    select
        seg.source_system, seg.claim_type, seg.source_table, seg.claim_id, seg.segment,
        seg._source_row_num, v.code_system, v.position, v.source_column, v.raw_value
    from seg
    cross join lateral (values
        ('ICD9-DX', 0, 'admtng_icd9_dgns_cd', seg.admtng_icd9_dgns_cd),
        {%- for i in range(1, 11) %}
        ('ICD9-DX', {{ i }}, 'icd9_dgns_cd_{{ i }}', seg.icd9_dgns_cd_{{ i }}),
        {%- endfor %}
        {%- for i in range(1, 7) %}
        ('ICD9-PROC', {{ i }}, 'icd9_prcdr_cd_{{ i }}', seg.icd9_prcdr_cd_{{ i }}),
        {%- endfor %}
        {%- for i in range(1, 46) %}
        ('HCPCS', {{ i }}, 'hcpcs_cd_{{ i }}', seg.hcpcs_cd_{{ i }}){{ ',' if not loop.last }}
        {%- endfor %}
    ) as v(code_system, position, source_column, raw_value)
    where v.raw_value is not null
      and not (seg.claim_type = 'OP' and v.code_system = 'ICD9-PROC')
)
select
    unpivoted.*,
    case code_system
        when 'ICD9-DX' then
            case
                when raw_value = 'OTHER'                              then 'PLACEHOLDER_CODE'   -- F5
                when raw_value ~ '^(\d{3,5}|V\d{2,4}|E\d{3,4})$'      then null                 -- valid ICD-9-CM dx format
                else 'INVALID_FORMAT'
            end
        when 'ICD9-PROC' then
            case
                when raw_value ~ '^\d{2,4}$'                          then null                 -- valid ICD-9-CM procedure format
                when raw_value ~ '^(\d{3,5}|V\d{2,4}|E\d{3,4})$'      then 'WRONG_CODE_SYSTEM'  -- a diagnosis in a procedure column (F3)
                else 'INVALID_FORMAT'
            end
        when 'HCPCS' then
            case
                when raw_value ~ '^[A-Z0-9]\d{3}[A-Z0-9]$'            then null                 -- CPT (Level I) or HCPCS Level II format
                when raw_value ~ '^\d+E\d+$'                          then 'SCI_NOTATION'       -- e.g. 201E5: Excel mangled the code (F4)
                when raw_value ~ '^0\d{3}$'                           then 'REVENUE_CODE'       -- e.g. 0851: UB-04 revenue code in the wrong field
                when raw_value ~ '^\d{1,4}$'                          then 'TRUNCATED'          -- e.g. 520: lost leading/trailing characters
                when raw_value ~ '[A-Za-z]'                           then 'NON_CODE_TEXT'      -- e.g. TOTAL, DIALY
                else 'INVALID_FORMAT'
            end
    end as reason_code
from unpivoted
