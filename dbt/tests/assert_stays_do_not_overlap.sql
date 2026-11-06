-- After merging transfers, a member's stays never overlap and readmissions are 1+ days later.
select * from (
    select member_key, admission_date,
           lag(discharge_date) over (partition by member_key order by admission_date) as prior_discharge
    from {{ ref('fct_inpatient_stay') }}) t
where admission_date <= prior_discharge
