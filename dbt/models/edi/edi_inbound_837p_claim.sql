{{ config(grants={'select': ['cc_steward']}) }}  -- SEC-1: direct identifiers, stewards only
-- EDI-2: one row per claim received in an inbound 837P, rebuilt from raw segments.
with seg as (select * from {{ ref('stg_x12__837p_segment') }}),
isa as (
    select _source_file, elements[15] as usage_indicator, elements[13] as isa_control
    from seg where segment_id = 'ISA'
),
receiver as (   -- loop 1000B: the payer the file was sent to
    select _source_file, elements[3] as receiver_name, elements[9] as receiver_id
    from seg where segment_id = 'NM1' and elements[1] = '40'
),
billing as (    -- loop 2010AA
    select _source_file, billing_seq, elements[3] as billing_name, elements[9] as billing_npi
    from seg where segment_id = 'NM1' and elements[1] = '85'
),
subscriber as ( -- loop 2010BA
    select _source_file, subscriber_seq, lower(elements[9]) as member_source_id,
           elements[3] as last_name, elements[4] as first_name
    from seg where segment_id = 'NM1' and elements[1] = 'IL'
),
sbr as (
    select _source_file, subscriber_seq, elements[9] as claim_filing_indicator
    from seg where segment_id = 'SBR'
),
dmg as (
    select _source_file, subscriber_seq, to_date(elements[2], 'YYYYMMDD') as birth_date, elements[3] as sex_code
    from seg where segment_id = 'DMG'
),
rendering as (  -- loop 2310B, inside the claim
    select _source_file, claim_seq, elements[9] as rendering_npi
    from seg where segment_id = 'NM1' and elements[1] = '82'
),
dx as (         -- HI: ABK = principal, ABF = other; codes in order
    select h._source_file, h.claim_seq,
           array_agg(split_part(e.code, h.component_sep, 2) order by e.pos) as icd10_codes
    from seg h
    cross join lateral unnest(h.elements) with ordinality as e(code, pos)
    where h.segment_id = 'HI'
    group by h._source_file, h.claim_seq
),
clm as (
    select _source_file, claim_seq, subscriber_seq, billing_seq, segment_num,
           elements[1] as claim_id, elements[2]::numeric(14,2) as total_charge,
           split_part(elements[5], component_sep, 1) as place_of_service
    from seg where segment_id = 'CLM'
)
select
    c._source_file,
    i.usage_indicator,
    i.isa_control,
    c.claim_seq,
    c.claim_id,
    c.total_charge,
    c.place_of_service,
    r.receiver_name                 as payer_name,
    b.billing_name,
    b.billing_npi,
    s.member_source_id,
    s.last_name,
    s.first_name,
    d.birth_date,
    d.sex_code,
    sb.claim_filing_indicator,
    rp.rendering_npi,
    dx.icd10_codes
from clm c
join isa i                on i._source_file = c._source_file
left join receiver r      on r._source_file = c._source_file
left join billing b       on b._source_file = c._source_file and b.billing_seq = c.billing_seq
left join subscriber s    on s._source_file = c._source_file and s.subscriber_seq = c.subscriber_seq
left join sbr sb          on sb._source_file = c._source_file and sb.subscriber_seq = c.subscriber_seq
left join dmg d           on d._source_file = c._source_file and d.subscriber_seq = c.subscriber_seq
left join rendering rp    on rp._source_file = c._source_file and rp.claim_seq = c.claim_seq
left join dx              on dx._source_file = c._source_file and dx.claim_seq = c.claim_seq
