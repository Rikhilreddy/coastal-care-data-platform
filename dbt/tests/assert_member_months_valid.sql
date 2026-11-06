-- A member cannot have more than 12 or fewer than 0 covered months in a year.
select * from {{ ref('fct_member_coverage_year') }} where member_months not between 0 and 12
