-- GOLD SCD-2 member dimension: one row per version of a member's location and plan.
-- Join a fact to the version that was true on its date:
--   on f.member_key = h.member_key and f.service_date >= h.valid_from
--                                   and f.service_date <  coalesce(h.valid_to, '9999-12-31')
select member_key, source_system, city, state, zip3, plan_name, line_of_business,
       dbt_valid_from::date                        as valid_from,
       dbt_valid_to::date                          as valid_to,
       (dbt_valid_to is null)                      as is_current,
       row_number() over (partition by member_key order by dbt_valid_from) as version
from {{ ref('member_history') }}
