-- depends_on: {{ source('bronze', 'nppes_npi_lookup') }}
-- API-1: latest NPPES registry answer per NPI (public provider data, not PHI).
-- The registry check is optional: before the first API run the bronze table does not exist
-- and this model is empty (same columns), so the platform still builds.
{% set rel = adapter.get_relation(database=target.database, schema='bronze', identifier='nppes_npi_lookup') %}
{% if rel is not none %}
with latest as (
    select distinct on (npi) *
    from {{ rel }}
    order by npi, fetched_at desc
)
select
    npi, lookup_status, fetched_at,
    jsonb_path_query_first(response, '$.results[0].enumeration_type') #>> '{}'               as entity_type,
    coalesce(jsonb_path_query_first(response, '$.results[0].basic.organization_name') #>> '{}',
             concat_ws(' ', jsonb_path_query_first(response, '$.results[0].basic.first_name') #>> '{}',
                            jsonb_path_query_first(response, '$.results[0].basic.last_name') #>> '{}'))   as provider_name,
    jsonb_path_query_first(response, '$.results[0].basic.status') #>> '{}'                    as registry_status,
    jsonb_path_query_first(response, '$.results[0].taxonomies[*] ? (@.primary == true).code') #>> '{}' as primary_taxonomy_code,
    jsonb_path_query_first(response, '$.results[0].taxonomies[*] ? (@.primary == true).desc') #>> '{}' as primary_taxonomy
from latest
{% else %}
select null::text as npi, null::text as lookup_status, null::timestamptz as fetched_at, null::text as entity_type,
       null::text as provider_name, null::text as registry_status, null::text as primary_taxonomy_code,
       null::text as primary_taxonomy
where false
{% endif %}
