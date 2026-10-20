-- CONV-4 governance: every SNOMED condition code arriving in bronze has a crosswalk row.
-- When a new Synthea/FHIR load brings a new code, the build fails until someone maps it,
-- instead of silently leaving diagnoses unconverted.
with used as (
    select distinct resource #>> '{code,coding,0,code}' as snomed_code,
                    resource #>> '{code,coding,0,display}' as description
    from {{ source('bronze', 'fhir_resource') }}
    where resource_type = 'Condition'
)
select u.*
from used u
left join {{ ref('snomed_icd10_crosswalk') }} x on x.snomed_code = u.snomed_code
where x.snomed_code is null
