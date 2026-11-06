-- GOLD reconciliation: no dollars are lost or invented between silver and gold.
-- Net paid per source and year in fct_claim = silver.claim_header, and the PMPM mart
-- (enrolled + unenrolled) adds back to the same total.
with s as (select source_system, claim_year, sum(paid_amount) as paid from {{ ref('claim_header') }} group by 1, 2),
g as (select source_system, claim_year, sum(paid_amount) as paid from {{ ref('fct_claim') }} group by 1, 2),
p as (select sum(paid_amount + paid_without_enrollment) as paid from {{ ref('mart_pmpm') }})
select 'fct_claim' as check_name, s.source_system, s.claim_year, s.paid, g.paid as gold_paid
from s full join g using (source_system, claim_year)
where s.paid is distinct from g.paid
union all
select 'mart_pmpm', null, null, (select sum(paid) from s), p.paid from p
where p.paid is distinct from (select sum(paid) from s)
