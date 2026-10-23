-- Reconciliation, FHIR diagnoses: every Claim.diagnosis[] entry in bronze lands exactly once,
-- either in silver.claim_diagnosis or in quarantine.code_exception (UNRESOLVED_REFERENCE).
with bronze as (
    select coalesce(sum(jsonb_array_length(resource -> 'diagnosis')), 0) as entries
    from {{ source('bronze', 'fhir_resource') }}
    where resource_type = 'Claim' and jsonb_typeof(resource -> 'diagnosis') = 'array'
),
landed as (
    select (select count(*) from {{ ref('claim_diagnosis') }} where source_system = 'SYNTHEA_FHIR')
         + (select count(*) from {{ ref('code_exception') }}  where source_system = 'SYNTHEA_FHIR') as entries
)
select b.entries as bronze_entries, l.entries as silver_plus_quarantine
from bronze b cross join landed l
where b.entries <> l.entries
