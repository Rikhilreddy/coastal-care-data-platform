-- A member cannot have more than 12 (or fewer than 0) covered months in a year, across all plans.
select member_key, coverage_year, sum(member_months) as months
from {{ ref('fct_member_coverage_year') }}
group by 1, 2
having sum(member_months) not between 0 and 12 or min(member_months) < 0
