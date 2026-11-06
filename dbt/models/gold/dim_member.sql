-- GOLD-1 member dimension. De-identified: no names, SSN, address or exact birth date
-- (HIPAA minimum necessary): analysts get birth year, age band, sex, state.
with base as (
    select m.source_system, m.member_source_id, m.birth_date, m.death_date, m.sex_code,
           m.first_coverage_year, m.last_coverage_year
    from {{ ref('member') }} m
),
state as (
    select distinct on (source_system, member_source_id) source_system, member_source_id, state_code
    from {{ ref('member_year') }} order by source_system, member_source_id, coverage_year desc
),
fhir_state as (
    select source_system, member_source_id, state from {{ ref('member_identity') }}
)
select
    md5(b.source_system || '|' || b.member_source_id)                    as member_key,
    b.source_system, b.member_source_id,
    extract(year from b.birth_date)::int                                 as birth_year,
    case when b.birth_date is null then 'UNKNOWN'
         when age(coalesce(b.death_date, current_date), b.birth_date) < interval '18 years' then '0-17'
         when age(coalesce(b.death_date, current_date), b.birth_date) < interval '45 years' then '18-44'
         when age(coalesce(b.death_date, current_date), b.birth_date) < interval '65 years' then '45-64'
         when age(coalesce(b.death_date, current_date), b.birth_date) < interval '75 years' then '65-74'
         else '75+' end                                                  as age_band,
    b.sex_code,
    coalesce(s.state_code, f.state)                                      as state,
    (b.death_date is not null)                                           as is_deceased,
    extract(year from b.death_date)::int                                 as death_year
from base b
left join state s using (source_system, member_source_id)
left join fhir_state f using (source_system, member_source_id)
