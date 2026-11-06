-- GOLD-2 cost per member per month (PMPM) by source, line of business, year and claim type.
-- PMPM = net paid / member months. Member months come only from enrollment; claims for
-- members with no enrollment that year are counted separately (they are a data-quality finding).
with mm as (
    select source_system, line_of_business, coverage_year as year, sum(member_months) as member_months
    from {{ ref('fct_member_coverage_year') }} group by 1, 2, 3
),
enrolled as (
    select distinct member_key, coverage_year as year from {{ ref('fct_member_coverage_year') }} where member_months > 0
),
paid as (
    select c.source_system, c.line_of_business, c.claim_year as year, c.claim_type,
           sum(c.paid_amount) filter (where e.member_key is not null)    as paid_enrolled,
           sum(c.paid_amount) filter (where e.member_key is null)        as paid_unenrolled,
           count(*)                                                      as claims
    from {{ ref('fct_claim') }} c
    left join enrolled e on e.member_key = c.member_key and e.year = c.claim_year
    group by 1, 2, 3, 4
)
select p.source_system, p.line_of_business, p.year, p.claim_type, p.claims, mm.member_months,
       coalesce(p.paid_enrolled, 0)                                       as paid_amount,
       coalesce(p.paid_unenrolled, 0)                                     as paid_without_enrollment,
       round(coalesce(p.paid_enrolled, 0) / nullif(mm.member_months, 0), 2) as pmpm
from paid p
left join mm using (source_system, line_of_business, year)
