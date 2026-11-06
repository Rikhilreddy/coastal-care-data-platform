{{ config(materialized='view') }}
-- SEC-1 masked identity for engineers: enough to debug a match or a load (initials, birth
-- year, ZIP3, last 4 of SSN), never enough to identify the person (HIPAA minimum necessary).
select source_system, member_source_id,
       left(first_name, 1) || '***'                                   as first_name,
       left(last_name, 1) || '***'                                    as last_name,
       extract(year from birth_date)::int                             as birth_year,
       case when ssn is not null then '***-**-' || right(ssn, 4) end  as ssn_last4,
       left(postal_code, 3) || '**'                                   as zip3,
       state
from {{ ref('member_identity') }}
