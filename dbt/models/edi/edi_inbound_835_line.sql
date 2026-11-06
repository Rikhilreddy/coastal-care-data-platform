-- EDI-3: one row per paid service line (SVC) in an 835, with its adjustments (CAS) pivoted.
-- CAS holds up to 6 (reason, amount, quantity) triplets after the group code.
with seg as (select * from {{ ref('stg_x12__835_segment') }}),
svc as (select _source_file, claim_seq, line_seq,
               split_part(elements[1], component_sep, 2) as procedure_code,
               elements[2]::numeric(14,2) as charge, elements[3]::numeric(14,2) as paid
        from seg where segment_id = 'SVC'),
cas as (
    select s._source_file, s.line_seq, s.elements[1] as group_code,
           s.elements[k] as reason_code, nullif(s.elements[k + 1], '')::numeric(14,2) as amount
    from seg s
    cross join lateral generate_series(2, 17, 3) as k
    where s.segment_id = 'CAS' and s.line_seq > 0 and coalesce(s.elements[k], '') <> ''
),
adj as (
    select _source_file, line_seq,
           coalesce(sum(amount) filter (where group_code = 'PR' and reason_code = '1'), 0) as deductible,
           coalesce(sum(amount) filter (where group_code = 'PR' and reason_code = '2'), 0) as coinsurance,
           coalesce(sum(amount) filter (where group_code = 'CO'), 0)                       as contractual,
           coalesce(sum(amount), 0)                                                       as total_adjustment
    from cas group by 1, 2
),
clp as (select _source_file, claim_seq, elements[1] as claim_id from seg where segment_id = 'CLP')
select v._source_file, c.claim_id,
       row_number() over (partition by v._source_file, v.claim_seq order by v.line_seq) as line_number,
       v.procedure_code, v.charge, v.paid,
       coalesce(a.deductible, 0) as deductible, coalesce(a.coinsurance, 0) as coinsurance,
       coalesce(a.contractual, 0) as contractual, coalesce(a.total_adjustment, 0) as total_adjustment
from svc v
join clp c       on c._source_file = v._source_file and c.claim_seq = v.claim_seq
left join adj a  on a._source_file = v._source_file and a.line_seq = v.line_seq
