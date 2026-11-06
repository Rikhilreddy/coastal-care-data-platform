{{ config(grants={'select': ['cc_steward']}) }}  -- SEC-1: direct identifiers, stewards only
-- Inbound 834 segments with loop context (EDI-4): member_seq counts INS (loop 2000), so every
-- segment knows which enrollment record it belongs to. Same positional technique as 837/835.
select
    s._source_file, s.segment_num, s.segment_id, s.elements,
    sum((s.segment_id = 'INS')::int) over w as member_seq
from {{ source('bronze', 'x12_segment') }} s
where s._source_file in (
    select _source_file from {{ source('bronze', 'x12_segment') }}
    where segment_id = 'ST' and elements[1] = '834'
)
window w as (partition by s._source_file order by s.segment_num)
