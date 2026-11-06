-- MPI step 1: one row per identity a source sends us: hospital facility MRNs (HL7 ADT) and
-- payer subscriber IDs (X12 834). Latest demographics per record.
with adt as (
    select distinct on (facility_mrn)
        'HL7_ADT'::text as source_system, facility_mrn as source_record_id,
        upper(last_name) as last_name, upper(first_name) as first_name, birth_date, sex_code,
        nullif(regexp_replace(ssn, '\D', '', 'g'), '') as ssn, left(postal_code, 5) as postal_code
    from {{ ref('hl7_adt_event') }}
    order by facility_mrn, event_ts desc
),
enrollment as (
    select distinct on (subscriber_id)
        'X12_834'::text as source_system, subscriber_id as source_record_id,
        upper(last_name) as last_name, upper(first_name) as first_name, birth_date, sex_code,
        nullif(regexp_replace(ssn, '\D', '', 'g'), '') as ssn, left(postal_code, 5) as postal_code
    from {{ ref('edi_inbound_834_member') }}
    order by subscriber_id, coverage_begin desc
)
select * from adt
union all
select * from enrollment
