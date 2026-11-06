{{ config(grants={'select': ['cc_steward']}) }}  -- SEC-1: direct identifiers, stewards only
-- EDI-4: one row per enrollment record (INS loop) received on an 834.
-- DTP qualifiers: 348 benefit begin, 349 benefit end (loop 2300).  NM109 is the SSN when NM108 = 34.
with seg as (select * from {{ ref('stg_x12__834_segment') }}),
hdr as (
    select _source_file,
           max(elements[15]) filter (where segment_id = 'ISA')                       as usage_indicator,
           max(elements[2])  filter (where segment_id = 'N1' and elements[1] = 'IN') as payer_name
    from seg group by _source_file
),
mem as (
    select _source_file, member_seq,
           max(elements[3]) filter (where segment_id = 'INS')                        as maintenance_type,
           max(elements[5]) filter (where segment_id = 'INS')                        as benefit_status,
           max(elements[2]) filter (where segment_id = 'REF' and elements[1] = '0F') as subscriber_id,
           max(elements[3]) filter (where segment_id = 'NM1' and elements[1] = 'IL') as last_name,
           max(elements[4]) filter (where segment_id = 'NM1' and elements[1] = 'IL') as first_name,
           max(case when segment_id = 'NM1' and elements[1] = 'IL' and elements[8] = '34' then elements[9] end) as ssn,
           max(elements[3]) filter (where segment_id = 'N4')                         as postal_code,
           max(elements[2]) filter (where segment_id = 'DMG')                        as birth_ccyymmdd,
           max(elements[3]) filter (where segment_id = 'DMG')                        as sex_code,
           max(elements[3]) filter (where segment_id = 'HD')                         as insurance_line,
           max(elements[3]) filter (where segment_id = 'DTP' and elements[1] = '348') as begin_ccyymmdd,
           max(elements[3]) filter (where segment_id = 'DTP' and elements[1] = '349') as end_ccyymmdd
    from seg where member_seq > 0
    group by _source_file, member_seq
)
select m._source_file, m.member_seq, h.usage_indicator, h.payer_name,
       {{ line_of_business('h.payer_name') }}                    as line_of_business,
       m.maintenance_type, m.benefit_status, m.subscriber_id, m.last_name, m.first_name, m.ssn,
       left(m.postal_code, 5) as postal_code, to_date(m.birth_ccyymmdd, 'YYYYMMDD') as birth_date, m.sex_code,
       m.insurance_line, to_date(m.begin_ccyymmdd, 'YYYYMMDD') as coverage_begin,
       to_date(nullif(m.end_ccyymmdd, ''), 'YYYYMMDD') as coverage_end
from mem m join hdr h using (_source_file)
