{{ config(grants={'select': ['cc_steward']}) }}  -- SEC-1: direct identifiers, stewards only
-- Inbound 837P segments with their LOOP CONTEXT (EDI-2).
-- X12 is positional: a segment belongs to the nearest loop opener above it. Running counts
-- over the file (window functions) turn position into keys:
--   billing_seq    = HL*..*20 (billing provider)     subscriber_seq = HL*..*22 (subscriber)
--   claim_seq      = CLM                             line_seq       = LX (service line)
select
    s._source_file,
    s.segment_num,
    s.segment_id,
    s.elements,
    s.component_sep,
    sum((s.segment_id = 'ST')::int)                                 over w as txn_seq,
    sum((s.segment_id = 'HL' and s.elements[3] = '20')::int)        over w as billing_seq,
    sum((s.segment_id = 'HL' and s.elements[3] = '22')::int)        over w as subscriber_seq,
    sum((s.segment_id = 'CLM')::int)                                over w as claim_seq,
    sum((s.segment_id = 'LX')::int)                                 over w as line_seq
from {{ source('bronze', 'x12_segment') }} s
where s._source_file in (
    select _source_file from {{ source('bronze', 'x12_segment') }}
    where segment_id = 'ST' and elements[1] = '837'
)
window w as (partition by s._source_file order by s.segment_num)
