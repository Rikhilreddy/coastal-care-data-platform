-- EDI-2: one row per service line received in an inbound 837P (LX + SV1 + DTP*472).
with seg as (select * from {{ ref('stg_x12__837p_segment') }}),
sv1 as (
    select _source_file, claim_seq, line_seq,
           split_part(elements[1], component_sep, 1) as code_qualifier,     -- HC = HCPCS/CPT
           split_part(elements[1], component_sep, 2) as procedure_code,
           elements[2]::numeric(14,2)                as line_charge,
           elements[4]::numeric                       as units
    from seg where segment_id = 'SV1'
),
dtp as (
    select _source_file, claim_seq, line_seq, to_date(elements[3], 'YYYYMMDD') as service_date
    from seg where segment_id = 'DTP' and elements[1] = '472' and line_seq > 0
),
clm as (
    select _source_file, claim_seq, elements[1] as claim_id, min(line_seq) as first_line_seq
    from seg where segment_id = 'CLM' group by 1, 2, 3
)
select
    v._source_file,
    c.claim_id,
    row_number() over (partition by v._source_file, v.claim_seq order by v.line_seq) as line_number,
    v.code_qualifier,
    v.procedure_code,
    v.line_charge,
    v.units,
    d.service_date
from sv1 v
join clm c      on c._source_file = v._source_file and c.claim_seq = v.claim_seq
left join dtp d on d._source_file = v._source_file and d.claim_seq = v.claim_seq and d.line_seq = v.line_seq
