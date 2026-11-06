-- GOLD-2 member months (the PMPM denominator), one row per member, coverage year and line of
-- business. A member-month is a calendar month with coverage on any day.
--   DE-SynPUF: months of Part A, Part B or HMO coverage per year (reported counts).
--   Synthea:   834 enrollment spans (EDI-4) linked to the member by the MPI; a month covered by
--              two plans (a plan change mid-month) counts once, for the plan that started last.
with synpuf as (
    select source_system, member_source_id, coverage_year, 'MEDICARE'::text as line_of_business,
           greatest(coalesce(part_a_months, 0), coalesce(part_b_months, 0), coalesce(hmo_months, 0)) as member_months
    from {{ ref('member_year') }}
    where source_system = 'DESYNPUF'
),
span_month as (
    select e.source_system, e.member_source_id, e.line_of_business, e.coverage_begin, m::date as month_start
    from {{ ref('member_enrollment') }} e
    cross join lateral generate_series(date_trunc('month', e.coverage_begin),
                                       date_trunc('month', coalesce(e.coverage_end, current_date)),
                                       interval '1 month') m
),
one_plan_per_month as (
    select distinct on (source_system, member_source_id, month_start) *
    from span_month
    order by source_system, member_source_id, month_start, coverage_begin desc, line_of_business
),
synthea as (
    select source_system, member_source_id, extract(year from month_start)::int as coverage_year,
           line_of_business, count(*)::int as member_months
    from one_plan_per_month group by 1, 2, 3, 4
)
select md5(source_system || '|' || member_source_id) as member_key, *
from (select * from synpuf union all select * from synthea) u
