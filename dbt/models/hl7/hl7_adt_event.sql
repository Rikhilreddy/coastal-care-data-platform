{{ config(grants={'select': ['cc_steward']}) }}  -- SEC-1: direct identifiers, stewards only
-- HL7-1: one row per ADT message (A01 admit, A03 discharge), fields picked by HL7 position.
-- PID-3 is a REPEATING field (~): the MR and SS identifiers are found by their type code (CX.5).
with seg as (select * from {{ source('bronze', 'hl7_segment') }}),
msh as (select message_control_id, _source_file, fields[7] as message_ts, split_part(fields[9], '^', 2) as event_type,
               fields[4] as sending_facility, fields[11] as processing_id
        from seg where segment_id = 'MSH'),
evn as (select message_control_id, fields[2] as event_ts from seg where segment_id = 'EVN'),
pid as (select message_control_id, fields, component_sep, repetition_sep from seg where segment_id = 'PID'),
pid_ids as (
    select p.message_control_id,
           max(split_part(r.id, p.component_sep, 1)) filter (where split_part(r.id, p.component_sep, 5) = 'MR') as facility_mrn,
           max(split_part(r.id, p.component_sep, 1)) filter (where split_part(r.id, p.component_sep, 5) = 'SS') as ssn
    from pid p cross join lateral unnest(string_to_array(p.fields[3], p.repetition_sep)) as r(id)
    group by p.message_control_id
),
pv1 as (select message_control_id, fields[2] as patient_class, fields[19] as visit_number,
               split_part(fields[7], '^', 1) as attending_npi, fields[44] as admit_ts, fields[45] as discharge_ts
        from seg where segment_id = 'PV1')
select
    m.message_control_id, m._source_file, m.event_type, m.processing_id, m.sending_facility,
    to_timestamp(nullif(e.event_ts, ''), 'YYYYMMDDHH24MISS')                     as event_ts,
    i.facility_mrn, i.ssn,
    split_part(p.fields[5], p.component_sep, 1)                                   as last_name,
    split_part(p.fields[5], p.component_sep, 2)                                   as first_name,
    to_date(nullif(p.fields[7], ''), 'YYYYMMDD')                                  as birth_date,
    p.fields[8]                                                                   as sex_code,
    split_part(p.fields[11], p.component_sep, 5)                                  as postal_code,
    v.patient_class, v.visit_number, v.attending_npi,
    to_timestamp(nullif(v.admit_ts, ''), 'YYYYMMDDHH24MISS')                     as admit_ts,
    to_timestamp(nullif(v.discharge_ts, ''), 'YYYYMMDDHH24MISS')                 as discharge_ts
from msh m
join evn e      using (message_control_id)
join pid p      using (message_control_id)
join pid_ids i  using (message_control_id)
join pv1 v      using (message_control_id)
