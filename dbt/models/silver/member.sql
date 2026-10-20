-- One row per member (stable demographics). STTM: silver.member
-- Birth date, sex and race come from the member's LATEST coverage year;
-- death date is the EARLIEST recorded across years (F16).
with years as (
    select
        btrim(desynpuf_id)                    as member_source_id,
        _file_year                            as coverage_year,
        {{ to_date_yyyymmdd('bene_birth_dt') }} as birth_date,
        {{ to_date_yyyymmdd('bene_death_dt') }} as death_date,
        btrim(bene_sex_ident_cd)              as sex_raw,
        btrim(bene_race_cd)                   as race_raw
    from {{ source('bronze', 'desynpuf_beneficiary') }}
),
latest as (
    select distinct on (member_source_id) *
    from years
    order by member_source_id, coverage_year desc
),
summary as (
    select
        member_source_id,
        min(coverage_year)          as first_coverage_year,
        max(coverage_year)          as last_coverage_year,
        min(death_date)             as death_date,
        count(distinct birth_date)  as birth_date_versions
    from years
    group by member_source_id
)
select
    'DESYNPUF'::text            as source_system,
    l.member_source_id,
    l.birth_date,
    s.death_date,
    case l.sex_raw when '1' then 'M' when '2' then 'F' else 'U' end as sex_code,
    case l.race_raw when '1' then 'WHITE' when '2' then 'BLACK'
                    when '3' then 'OTHER' when '5' then 'HISPANIC' else 'UNKNOWN' end as race_code,
    s.first_coverage_year,
    s.last_coverage_year,
    (s.birth_date_versions > 1) as birth_date_conflict
from latest l
join summary s using (member_source_id)
