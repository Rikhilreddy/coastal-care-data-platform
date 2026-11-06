{{ config(grants={'select': ['cc_steward']}) }}  -- SEC-1: direct identifiers, stewards only
-- One row per FHIR Patient (Synthea), typed. STTM: docs/mapping/sttm_fhir.csv
-- JSONPath (jsonb_path_query_first) selects array elements by MEANING, not position:
-- e.g. "the identifier whose system is SSN", "the race extension", wherever they sit.
{%- set race_url = 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-race' %}
{%- set eth_url  = 'http://hl7.org/fhir/us/core/StructureDefinition/us-core-ethnicity' %}
with p as (
    select resource as r, _batch_id, _source_file, _source_entry_num
    from {{ source('bronze', 'fhir_resource') }}
    where resource_type = 'Patient'
)
select
    'SYNTHEA_FHIR'::text                                         as source_system,
    r ->> 'id'                                                   as member_source_id,
    left(r ->> 'birthDate', 10)::date                            as birth_date,
    left(r ->> 'deceasedDateTime', 10)::date                     as death_date,   -- local date as recorded
    case r ->> 'gender' when 'male' then 'M' when 'female' then 'F' else 'U' end as sex_code,
    -- OMB race / ethnicity codes mapped to the CMS categories used by silver.member
    -- (CMS counts Hispanic as a race category, so ethnicity wins when Hispanic)
    case
        when jsonb_path_query_first(r, '$.extension[*] ? (@.url == "{{ eth_url }}").extension[*] ? (@.url == "ombCategory").valueCoding.code') #>> '{}' = '2135-2' then 'HISPANIC'
        -- coalesce to '' first: CASE x WHEN NULL never matches (NULL = NULL is not true)
        else case coalesce(jsonb_path_query_first(r, '$.extension[*] ? (@.url == "{{ race_url }}").extension[*] ? (@.url == "ombCategory").valueCoding.code') #>> '{}', '')
                 when '2106-3' then 'WHITE'
                 when '2054-5' then 'BLACK'
                 when ''       then 'UNKNOWN'
                 else 'OTHER'
             end
    end                                                          as race_code,
    -- identity attributes (restricted; exposed only via silver.member_identity)
    jsonb_path_query_first(r, '$.name[*] ? (@.use == "official").given[0]') #>> '{}'  as first_name,
    jsonb_path_query_first(r, '$.name[*] ? (@.use == "official").family')   #>> '{}'  as last_name,
    jsonb_path_query_first(r, '$.identifier[*] ? (@.system == "http://hl7.org/fhir/sid/us-ssn").value') #>> '{}' as ssn,
    jsonb_path_query_first(r, '$.identifier[*] ? (@.type.coding[*].code == "MR").value') #>> '{}'         as mrn,
    r #>> '{address,0,line,0}'                                   as address_line,
    r #>> '{address,0,city}'                                     as city,
    r #>> '{address,0,state}'                                    as state,
    r #>> '{address,0,postalCode}'                               as postal_code,
    jsonb_path_query_first(r, '$.telecom[*] ? (@.system == "phone").value') #>> '{}' as phone,
    _batch_id,
    _source_file,
    _source_entry_num
from p
