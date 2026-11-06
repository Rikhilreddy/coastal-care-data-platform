-- GOLD-3 inpatient stays. Claims that overlap or touch (next admission on or before the prior
-- discharge, i.e. a transfer or an interim bill) are merged into one stay (gaps and islands).
with ip as (
    select member_key, source_system, line_of_business, claim_id, paid_amount,
           admission_date, coalesce(discharge_date, claim_thru_date) as discharge_date
    from {{ ref('fct_claim') }}
    where claim_type = 'IP' and not is_adjustment and admission_date is not null
),
flagged as (
    select *, case when admission_date <= max(discharge_date) over (
                       partition by member_key order by admission_date, discharge_date
                       rows between unbounded preceding and 1 preceding) then 0 else 1 end as new_stay
    from ip
),
numbered as (
    select *, sum(new_stay) over (partition by member_key order by admission_date, discharge_date) as stay_seq
    from flagged
)
select md5(member_key || '|' || stay_seq)                     as stay_key,
       member_key, min(source_system) as source_system, min(line_of_business) as line_of_business, stay_seq,
       min(admission_date) as admission_date, max(discharge_date) as discharge_date,
       max(discharge_date) - min(admission_date)              as length_of_stay,
       count(*)                                               as claims_merged,
       sum(paid_amount)                                       as paid_amount
from numbered
group by member_key, stay_seq
