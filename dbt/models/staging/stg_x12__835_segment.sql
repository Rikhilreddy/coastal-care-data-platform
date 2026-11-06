{{ config(grants={'select': ['cc_steward']}) }}  -- SEC-1: direct identifiers, stewards only
-- Inbound 835 segments with loop context (EDI-3): payment_seq = ST (one payment per payee),
-- claim_seq = CLP, line_seq = SVC. Same positional technique as the 837 parser.
select
    s._source_file, s.segment_num, s.segment_id, s.elements, s.component_sep,
    sum((s.segment_id = 'ST')::int)  over w as payment_seq,
    sum((s.segment_id = 'CLP')::int) over w as claim_seq,
    sum((s.segment_id = 'SVC')::int) over w as line_seq
from {{ source('bronze', 'x12_segment') }} s
where s._source_file in (
    select _source_file from {{ source('bronze', 'x12_segment') }}
    where segment_id = 'ST' and elements[1] = '835'
)
window w as (partition by s._source_file order by s.segment_num)
