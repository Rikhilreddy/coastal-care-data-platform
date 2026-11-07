{{ config(materialized='ephemeral') }}  -- compiled into the snapshot, so --vars as_of_date applies on every run
-- SCD-2 source: each member's tracked attributes AS OF a date (default: today).
-- Tracked: where the member lives (city, state, ZIP3; never street or full ZIP: HIPAA
-- minimum necessary) and the health plan they are enrolled in on that date (from the 834).
-- The snapshot `member_history` records every change to these as a new version.
-- Replaying history: dbt snapshot --vars '{as_of_date: "2019-01-01"}' (always moving forward).
{% set as_of = var('as_of_date', none) %}
with asof as (select {{ "'" ~ as_of ~ "'::date" if as_of else "current_date" }} as d),
plan as (
    select distinct on (e.member_source_id) e.member_source_id, e.payer_name, e.line_of_business
    from {{ ref('member_enrollment') }} e cross join asof
    where e.coverage_begin <= asof.d and coalesce(e.coverage_end, '9999-12-31') >= asof.d
    order by e.member_source_id, e.coverage_begin desc, e.payer_name
)
select md5(i.source_system || '|' || i.member_source_id)      as member_key,
       i.source_system, i.member_source_id,
       upper(i.city) as city, i.state, left(i.postal_code, 3)    as zip3,
       coalesce(p.payer_name, 'NOT ENROLLED')                    as plan_name,
       coalesce(p.line_of_business, 'NONE')                      as line_of_business,
       asof.d::timestamp                                         as as_of_ts
from {{ ref('member_identity') }} i
cross join asof
left join plan p on p.member_source_id = i.member_source_id
where i.source_system = 'SYNTHEA_FHIR'
