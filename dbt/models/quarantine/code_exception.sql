-- One row per rejected code VALUE (all sources). The claim stays in silver; only the bad
-- value is excluded. Reason codes: docs/profiling/desynpuf_findings.md (F3-F5) and
-- UNRESOLVED_REFERENCE (FHIR Claim.diagnosis pointing to a Condition not in the bundle).
select source_system, source_table, claim_type, claim_id, segment, _source_row_num,
       source_column, code_system, raw_value as original_value, reason_code
from {{ ref('int_claim_code_value') }}
where reason_code is not null
union all
select source_system, source_table, claim_type, claim_id, segment, _source_row_num,
       'diagnosis[' || dx_position || '].diagnosisReference' as source_column,
       'SNOMEDCT'                                            as code_system,
       original_reference                                    as original_value,
       'UNRESOLVED_REFERENCE'                                as reason_code
from {{ ref('int_fhir__claim_diagnosis') }}
where is_unresolved
