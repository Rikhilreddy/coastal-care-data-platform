-- One row per rejected claim segment (whole row). Kept, never deleted, and counted
-- in reconciliation: bronze = silver + quarantine, in rows and dollars.
select
    source_system,
    source_table,
    claim_type,
    claim_id,
    segment,
    member_source_id,
    'ORPHAN_SEGMENT'::text  as reason_code,     -- F12: continuation segment with no segment 1
    paid_amount,
    _batch_id,
    _source_file,
    _source_row_num
from {{ ref('stg_desynpuf__claim_segment') }}
where is_orphan_segment
