-- FHIR part of silver.claim_header. Same columns, same order as int_desynpuf__claim_header.
-- claim_type uses the canonical set: IP / OP (facility), PROF (professional), RX (pharmacy).
-- Institutional claims are split IP/OP by the billed Encounter's class (IMP/ACUTE/NONAC = inpatient).
select
    source_system,
    claim_id,
    case
        when source_claim_type = 'pharmacy'     then 'RX'
        when source_claim_type = 'professional' then 'PROF'
        when encounter_class in ('IMP', 'ACUTE', 'NONAC') then 'IP'
        else 'OP'
    end                                         as claim_type,
    source_claim_type,
    payer_name,
    member_source_id,
    1                                           as segment_count,       -- FHIR claims are not segmented
    claim_from_date,
    claim_thru_date,
    extract(year from claim_thru_date)::int     as claim_year,
    -- Admission dates only on the facility (institutional) inpatient claim. A pharmacy or
    -- professional claim written DURING a stay is not an admission (readmission logic depends on this).
    case when source_claim_type = 'institutional' and encounter_class in ('IMP', 'ACUTE', 'NONAC')
         then claim_from_date end               as admission_date,
    case when source_claim_type = 'institutional' and encounter_class in ('IMP', 'ACUTE', 'NONAC')
         then claim_thru_date end               as discharge_date,
    provider_id,
    null::text                                  as attending_npi,       -- from EOB careTeam in a later ticket
    null::text                                  as operating_npi,
    null::text                                  as other_npi,
    null::text                                  as drg_code,            -- Synthea does not group DRGs
    null::int                                   as utilization_days,
    billed_amount,
    coalesce(paid_amount, 0)                    as paid_amount,         -- EOB payment.amount
    0::numeric(14,2)                            as primary_payer_paid_amount,
    null::numeric(14,2)                         as pass_thru_per_diem_amount,
    null::numeric(14,2)                         as ip_deductible_amount,
    null::numeric(14,2)                         as part_a_coinsurance_amount,
    null::numeric(14,2)                         as blood_deductible_amount,
    null::numeric(14,2)                         as part_b_deductible_amount,
    null::numeric(14,2)                         as part_b_coinsurance_amount,
    (coalesce(paid_amount, 0) < 0)              as is_adjustment,
    (diagnosis_count = 0 and source_claim_type <> 'pharmacy') as primary_dx_missing,
    'bronze.fhir_resource'::text                as source_table,
    _batch_id,
    _source_file,
    array[_source_entry_num::bigint]            as _source_row_nums
from {{ ref('stg_fhir__claim') }}
