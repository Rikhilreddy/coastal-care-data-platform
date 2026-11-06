-- HL7-1 completeness: every inpatient FHIR encounter that has been sent has exactly one A01,
-- and exactly one A03 once it has ended; admit/discharge times equal the encounter's.
with sent as (select distinct visit_number from {{ ref('hl7_adt_event') }}),
enc as (
    select resource_id as encounter_id,
           to_timestamp(left(regexp_replace(resource #>> '{period,start}', '\D', '', 'g'), 14), 'YYYYMMDDHH24MISS') as start_ts,
           to_timestamp(left(regexp_replace(resource #>> '{period,end}', '\D', '', 'g'), 14), 'YYYYMMDDHH24MISS') as end_ts
    from {{ source('bronze', 'fhir_resource') }}
    where resource_type = 'Encounter' and resource #>> '{class,code}' in ('IMP', 'ACUTE', 'NONAC')
      and resource_id in (select visit_number from sent)
),
ev as (
    select visit_number,
           count(*) filter (where event_type = 'A01') as a01, count(*) filter (where event_type = 'A03') as a03,
           max(admit_ts) as admit_ts, max(discharge_ts) as discharge_ts
    from {{ ref('hl7_adt_event') }} group by visit_number
)
select e.encounter_id, v.a01, v.a03
from enc e join ev v on v.visit_number = e.encounter_id
where v.a01 <> 1 or (e.end_ts is not null and v.a03 <> 1)
   or v.admit_ts <> e.start_ts or (e.end_ts is not null and v.discharge_ts <> e.end_ts)
