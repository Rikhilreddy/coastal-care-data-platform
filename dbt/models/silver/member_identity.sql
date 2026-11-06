{{ config(meta={'pii': 'restricted'}, grants={'select': ['cc_steward']}) }}
-- RESTRICTED: direct identifiers (name, SSN, MRN, address, phone), one row per member.
-- Kept apart from silver.member so analysts can use demographics without identifiers
-- (HIPAA minimum necessary). Only the MPI/matching process and admin roles read this
-- table (role grants in Sprint 4). DE-SynPUF carries no identifiers.
select source_system, member_source_id, first_name, last_name, birth_date, ssn, mrn,
       address_line, city, state, postal_code, phone, _batch_id, _source_file
from {{ ref('stg_fhir__patient') }}
