-- GOLD-3 all-cause 30-day readmissions (simplified CMS/HEDIS logic, documented in the spec).
-- Index stay: the member was discharged alive and the data covers 30 days after discharge.
-- Readmission: another stay admitted 1-30 days after the index discharge.
-- Not applied (backlog): planned-readmission exclusions, which need the CMS PR algorithm.
with stays as (select * from {{ ref('fct_inpatient_stay') }}),
data_end as (select max(claim_thru_date) as last_date from {{ ref('fct_claim') }}),
idx as (
    select s.*, lead(s.admission_date) over (partition by s.member_key order by s.admission_date) as next_admission
    from stays s
)
select i.stay_key, i.member_key, i.source_system, i.line_of_business, i.admission_date, i.discharge_date,
       i.next_admission,
       (i.next_admission - i.discharge_date)                                   as days_to_readmit,
       coalesce(i.next_admission - i.discharge_date between 1 and 30, false)   as is_readmitted_30d
from idx i cross join data_end e
join {{ ref('member') }} m on md5(m.source_system || '|' || m.member_source_id) = i.member_key
where (m.death_date is null or m.death_date > i.discharge_date)
  and i.discharge_date <= e.last_date - 30
