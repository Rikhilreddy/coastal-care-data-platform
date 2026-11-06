-- GOLD-2 member months (the PMPM denominator), one row per member and coverage year.
-- DE-SynPUF reports months of Part A, Part B and HMO coverage per year; a member-month is a
-- month with any medical coverage. Synthea members get enrollment from the 834 (EDI-4).
select
    md5(source_system || '|' || member_source_id)                        as member_key,
    source_system, member_source_id, coverage_year,
    'MEDICARE'::text                                                     as line_of_business,
    greatest(coalesce(part_a_months, 0), coalesce(part_b_months, 0), coalesce(hmo_months, 0)) as member_months
from {{ ref('member_year') }}
where source_system = 'DESYNPUF'
