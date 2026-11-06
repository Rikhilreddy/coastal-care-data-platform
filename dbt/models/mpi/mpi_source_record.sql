-- MPI step 1: one row per identity a source sends us (here: hospital facility MRNs from ADT).
-- Latest demographics per record. 834 subscribers join this model in EDI-4.
select distinct on (facility_mrn)
    'HL7_ADT'::text as source_system, facility_mrn as source_record_id,
    upper(last_name) as last_name, upper(first_name) as first_name, birth_date, sex_code,
    nullif(regexp_replace(ssn, '\D', '', 'g'), '') as ssn, left(postal_code, 5) as postal_code
from {{ ref('hl7_adt_event') }}
order by facility_mrn, event_ts desc
