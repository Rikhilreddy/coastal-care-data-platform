-- One row per FHIR Claim with its ExplanationOfBenefit (H2: exactly one each) and the
-- class of the Encounter it bills. STTM: docs/mapping/sttm_fhir.csv
with claim as (
    select resource as r, resource_id, _batch_id, _source_file, _source_entry_num
    from {{ source('bronze', 'fhir_resource') }}
    where resource_type = 'Claim'
),
eob as (
    select regexp_replace(resource #>> '{claim,reference}', '^(urn:uuid:|Claim/)', '') as claim_id,
           (resource #>> '{payment,amount,value}')::numeric(14,2)                       as paid_amount
    from {{ source('bronze', 'fhir_resource') }}
    where resource_type = 'ExplanationOfBenefit'
),
encounter as (
    select resource_id as encounter_id,
           resource #>> '{class,code}' as encounter_class
    from {{ source('bronze', 'fhir_resource') }}
    where resource_type = 'Encounter'
)
select
    'SYNTHEA_FHIR'::text                                                        as source_system,
    c.resource_id                                                               as claim_id,
    c.r #>> '{type,coding,0,code}'                                              as source_claim_type,
    regexp_replace(c.r #>> '{patient,reference}', '^(urn:uuid:|Patient/)', '')  as member_source_id,
    left(c.r #>> '{billablePeriod,start}', 10)::date                            as claim_from_date,
    left(c.r #>> '{billablePeriod,end}', 10)::date                              as claim_thru_date,
    regexp_replace(c.r #>> '{item,0,encounter,0,reference}', '^(urn:uuid:|Encounter/)', '') as encounter_id,
    e.encounter_class,
    c.r #>> '{insurance,0,coverage,display}'                                    as payer_name,
    regexp_replace(c.r #>> '{provider,reference}', '^.*[|/:]', '')              as provider_id,
    (c.r #>> '{total,value}')::numeric(14,2)                                    as billed_amount,
    x.paid_amount,
    coalesce(jsonb_array_length(c.r -> 'diagnosis'), 0)                         as diagnosis_count,
    c._batch_id,
    c._source_file,
    c._source_entry_num
from claim c
left join eob x       on x.claim_id = c.resource_id
left join encounter e on e.encounter_id = regexp_replace(c.r #>> '{item,0,encounter,0,reference}', '^(urn:uuid:|Encounter/)', '')
