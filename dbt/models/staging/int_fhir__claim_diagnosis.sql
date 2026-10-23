-- FHIR diagnoses on claims (CONV-4). One row per Claim.diagnosis[] entry, resolved to its
-- Condition (SNOMED CT) and converted through the governed crosswalk.
-- ONLY APPROVED crosswalk rows produce an ICD-10-CM code; everything else is labelled,
-- not guessed: PENDING_REVIEW, NOT_CODABLE, REJECTED, NOT_IN_CROSSWALK.
-- Entries whose Condition cannot be found are flagged and routed to quarantine.code_exception.
with claim as (
    select resource_id as claim_id, resource as r, _source_entry_num
    from {{ source('bronze', 'fhir_resource') }}
    where resource_type = 'Claim'
),
entries as (
    select
        c.claim_id,
        c._source_entry_num,
        (d ->> 'sequence')::int                                              as dx_position,
        d #>> '{diagnosisReference,reference}'                               as reference,
        regexp_replace(d #>> '{diagnosisReference,reference}', '^(urn:uuid:|Condition/)', '') as condition_id
    from claim c
    cross join lateral jsonb_array_elements(c.r -> 'diagnosis') as d
    where jsonb_typeof(c.r -> 'diagnosis') = 'array'
),
condition as (
    select resource_id                          as condition_id,
           resource #>> '{code,coding,0,system}' as code_system_url,
           resource #>> '{code,coding,0,code}'   as snomed_code
    from {{ source('bronze', 'fhir_resource') }}
    where resource_type = 'Condition'
)
select
    'SYNTHEA_FHIR'::text                         as source_system,
    e.claim_id,
    h.claim_type,
    1                                            as segment,
    e.dx_position,
    case when e.dx_position = 1 then 'PRINCIPAL' else 'SECONDARY' end as dx_role,
    'SNOMEDCT'::text                             as source_code_system,
    k.snomed_code                                as source_code,
    case when x.review_status = 'APPROVED' and x.category <> 'NOT_CODABLE'
         then x.icd10_code end                   as icd10_code,
    case
        when x.snomed_code is null               then 'NOT_IN_CROSSWALK'
        when x.review_status = 'REJECTED'        then 'REJECTED'
        when x.review_status <> 'APPROVED'       then 'PENDING_REVIEW'
        when x.category = 'NOT_CODABLE'          then 'NOT_CODABLE'
        else 'CROSSWALK'
    end                                          as conversion_method,
    case when x.review_status = 'APPROVED' then x.reviewed_by end as conversion_decided_by,
    case when x.review_status = 'APPROVED' and x.category <> 'NOT_CODABLE'
         then i.is_billable end                  as icd10_billable,
    x.sensitive                                  as is_sensitive,       -- known even while pending
    'bronze.fhir_resource'::text                 as source_table,
    e._source_entry_num::bigint                  as _source_row_num,
    (k.condition_id is null)                     as is_unresolved,
    e.reference                                  as original_reference
from entries e
left join condition k                             on k.condition_id = e.condition_id
left join {{ ref('snomed_icd10_crosswalk') }} x   on x.snomed_code = k.snomed_code
left join {{ source('ref', 'icd10cm') }} i        on i.icd10_code = x.icd10_code
left join {{ ref('int_fhir__claim_header') }} h   on h.claim_id = e.claim_id
