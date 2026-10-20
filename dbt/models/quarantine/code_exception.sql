-- One row per rejected code VALUE. The claim itself stays in silver; only the bad
-- value is excluded. Reason codes: docs/profiling/desynpuf_findings.md (F3, F4, F5).
select
    source_system,
    source_table,
    claim_type,
    claim_id,
    segment,
    _source_row_num,
    source_column,
    code_system,
    raw_value      as original_value,
    reason_code
from {{ ref('int_claim_code_value') }}
where reason_code is not null
