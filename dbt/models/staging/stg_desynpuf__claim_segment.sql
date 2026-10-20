-- One row per bronze claim segment (inpatient + outpatient), typed and trimmed. No rows dropped.
-- Every downstream claims model reads from here, so cleaning rules live in one place.
-- Columns that exist in only one claim type are NULL for the other.
-- Code columns stay TEXT (F10) and are classified later in int_claim_code_value.


with inpatient as (
    select
        'IP'::text                      as claim_type,
        'bronze.desynpuf_inpatient'::text as source_table,
        b.*,
        null::text as nch_bene_ptb_ddctbl_amt,
        null::text as nch_bene_ptb_coinsrnc_amt
    from {{ source('bronze', 'desynpuf_inpatient') }} b
),
outpatient as (
    select
        'OP'::text                      as claim_type,
        'bronze.desynpuf_outpatient'::text as source_table,
        b.*,
        null::text as clm_admsn_dt,
        null::text as nch_bene_dschrg_dt,
        null::text as clm_drg_cd,
        null::text as clm_utlztn_day_cnt,
        null::text as clm_pass_thru_per_diem_amt,
        null::text as nch_bene_ip_ddctbl_amt,
        null::text as nch_bene_pta_coinsrnc_lblty_am
    from {{ source('bronze', 'desynpuf_outpatient') }} b
),
unioned as (
    -- Explicit column list: union by NAME, never by position
    {% for t in ['inpatient', 'outpatient'] %}
    select
        claim_type, source_table, desynpuf_id, clm_id, segment, clm_from_dt, clm_thru_dt,
        prvdr_num, at_physn_npi, op_physn_npi, ot_physn_npi,
        clm_pmt_amt, nch_prmry_pyr_clm_pd_amt, nch_bene_blood_ddctbl_lblty_am,
        clm_admsn_dt, nch_bene_dschrg_dt, clm_drg_cd, clm_utlztn_day_cnt,
        clm_pass_thru_per_diem_amt, nch_bene_ip_ddctbl_amt, nch_bene_pta_coinsrnc_lblty_am,
        nch_bene_ptb_ddctbl_amt, nch_bene_ptb_coinsrnc_amt,
        admtng_icd9_dgns_cd,
        {% for i in range(1, 11) %}icd9_dgns_cd_{{ i }}, {% endfor %}
        {% for i in range(1, 7) %}icd9_prcdr_cd_{{ i }}, {% endfor %}
        {% for i in range(1, 46) %}hcpcs_cd_{{ i }}, {% endfor %}
        _batch_id, _source_file, _source_row_num
    from {{ t }}
    {% if not loop.last %}union all{% endif %}
    {% endfor %}
),
typed as (
    select
        'DESYNPUF'::text                                   as source_system,
        claim_type,
        source_table,
        btrim(clm_id)                                      as claim_id,
        btrim(segment)::int                                as segment,
        btrim(desynpuf_id)                                 as member_source_id,
        {{ to_date_yyyymmdd('clm_from_dt') }}              as claim_from_date,
        {{ to_date_yyyymmdd('clm_thru_dt') }}              as claim_thru_date,
        {{ to_date_yyyymmdd('clm_admsn_dt') }}             as admission_date,
        {{ to_date_yyyymmdd('nch_bene_dschrg_dt') }}       as discharge_date,
        nullif(btrim(prvdr_num), '')                       as provider_id,
        nullif(btrim(at_physn_npi), '')                    as attending_npi,
        nullif(btrim(op_physn_npi), '')                    as operating_npi,
        nullif(btrim(ot_physn_npi), '')                    as other_npi,
        lpad(nullif(btrim(clm_drg_cd), ''), 3, '0')        as drg_code,
        nullif(btrim(clm_utlztn_day_cnt), '')::numeric::int as utilization_days,
        {{ to_money('clm_pmt_amt') }}                      as paid_amount,
        {{ to_money('nch_prmry_pyr_clm_pd_amt') }}         as primary_payer_paid_amount,
        {{ to_money('clm_pass_thru_per_diem_amt') }}       as pass_thru_per_diem_amount,
        {{ to_money('nch_bene_ip_ddctbl_amt') }}           as ip_deductible_amount,
        {{ to_money('nch_bene_pta_coinsrnc_lblty_am') }}   as part_a_coinsurance_amount,
        {{ to_money('nch_bene_blood_ddctbl_lblty_am') }}   as blood_deductible_amount,
        {{ to_money('nch_bene_ptb_ddctbl_amt') }}          as part_b_deductible_amount,
        {{ to_money('nch_bene_ptb_coinsrnc_amt') }}        as part_b_coinsurance_amount,
        nullif(btrim(admtng_icd9_dgns_cd), '')             as admtng_icd9_dgns_cd,
        {% for i in range(1, 11) %}nullif(btrim(icd9_dgns_cd_{{ i }}), '') as icd9_dgns_cd_{{ i }},
        {% endfor %}
        {% for i in range(1, 7) %}nullif(btrim(icd9_prcdr_cd_{{ i }}), '') as icd9_prcdr_cd_{{ i }},
        {% endfor %}
        {% for i in range(1, 46) %}nullif(btrim(hcpcs_cd_{{ i }}), '') as hcpcs_cd_{{ i }},
        {% endfor %}
        _batch_id,
        _source_file,
        _source_row_num
    from unioned
)
select
    typed.*,
    -- F12: a continuation segment whose claim has no segment 1 cannot be placed on a claim
    not bool_or(segment = 1) over (partition by source_system, claim_id) as is_orphan_segment
from typed
