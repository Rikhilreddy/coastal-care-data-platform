-- DE-SynPUF part of silver.claim_header: one row per claim, all segments rolled up (F1, F11).
-- Header attributes and dates come from segment 1 (segment 2 has no dates);
-- dollar amounts are SUMMED across all segments (segment 2 carries $16.5M).
-- Orphan segments (no segment 1) are excluded here and kept in quarantine.claim_exception.
with seg as (
    select * from {{ ref('stg_desynpuf__claim_segment') }}
    where not is_orphan_segment
),
totals as (
    select
        source_system,
        claim_id,
        count(*)                               as segment_count,
        coalesce(sum(paid_amount), 0)          as paid_amount,
        coalesce(sum(primary_payer_paid_amount), 0) as primary_payer_paid_amount,
        sum(ip_deductible_amount)              as ip_deductible_amount,
        sum(part_a_coinsurance_amount)         as part_a_coinsurance_amount,
        sum(blood_deductible_amount)           as blood_deductible_amount,
        sum(part_b_deductible_amount)          as part_b_deductible_amount,
        sum(part_b_coinsurance_amount)         as part_b_coinsurance_amount,
        array_agg(_source_row_num order by segment) as _source_row_nums
    from seg
    group by source_system, claim_id
)
select
    s1.source_system,
    s1.claim_id,
    s1.claim_type,
    case s1.claim_type when 'IP' then 'inpatient' else 'outpatient' end as source_claim_type,
    'Medicare'::text                           as payer_name,                -- legacy plan is Medicare FFS
    s1.member_source_id,
    t.segment_count,
    s1.claim_from_date,
    s1.claim_thru_date,
    extract(year from s1.claim_thru_date)::int as claim_year,      -- F13: thru date, not from date
    s1.admission_date,
    s1.discharge_date,
    s1.provider_id,
    s1.attending_npi,
    s1.operating_npi,
    s1.other_npi,
    s1.drg_code,
    s1.utilization_days,
    null::numeric(14,2)                        as billed_amount,             -- not in DE-SynPUF
    t.paid_amount,
    t.primary_payer_paid_amount,
    s1.pass_thru_per_diem_amount,                                  -- a daily rate: not summed
    t.ip_deductible_amount,
    t.part_a_coinsurance_amount,
    t.blood_deductible_amount,
    t.part_b_deductible_amount,
    t.part_b_coinsurance_amount,
    (t.paid_amount < 0)                                   as is_adjustment,        -- F2
    (s1.icd9_dgns_cd_1 is null or s1.icd9_dgns_cd_1 = 'OTHER') as primary_dx_missing, -- F5
    s1.source_table,
    s1._batch_id,
    s1._source_file,
    t._source_row_nums
from seg s1
join totals t
  on t.source_system = s1.source_system
 and t.claim_id = s1.claim_id
where s1.segment = 1
