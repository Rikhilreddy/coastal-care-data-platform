-- One row per member per coverage year. STTM: docs/mapping/sttm_desynpuf.csv (silver.member_year)
with src as (
    select * from {{ source('bronze', 'desynpuf_beneficiary') }}
)
select
    'DESYNPUF'::text                                  as source_system,
    btrim(desynpuf_id)                                as member_source_id,
    _file_year                                        as coverage_year,
    lpad(btrim(sp_state_code), 2, '0')                as state_code,
    lpad(btrim(bene_county_cd), 3, '0')               as county_code,
    nullif(btrim(bene_hi_cvrage_tot_mons), '')::int   as part_a_months,
    nullif(btrim(bene_smi_cvrage_tot_mons), '')::int  as part_b_months,
    nullif(btrim(bene_hmo_cvrage_tot_mons), '')::int  as hmo_months,
    nullif(btrim(plan_cvrg_mos_num), '')::int         as part_d_months,
    case btrim(bene_esrd_ind) when 'Y' then true when '0' then false end as esrd_flag,
    {{ cms_flag('sp_alzhdmta') }}  as has_alzheimers,
    {{ cms_flag('sp_chf') }}       as has_chf,
    {{ cms_flag('sp_chrnkidn') }}  as has_ckd,
    {{ cms_flag('sp_cncr') }}      as has_cancer,
    {{ cms_flag('sp_copd') }}      as has_copd,
    {{ cms_flag('sp_depressn') }}  as has_depression,
    {{ cms_flag('sp_diabetes') }}  as has_diabetes,
    {{ cms_flag('sp_ischmcht') }}  as has_ischemic_heart,
    {{ cms_flag('sp_osteoprs') }}  as has_osteoporosis,
    {{ cms_flag('sp_ra_oa') }}     as has_ra_oa,
    {{ cms_flag('sp_strketia') }}  as has_stroke_tia,
    coalesce(nullif(btrim(medreimb_ip), ''), '0')::numeric(14,2)  as reported_ip_medicare_paid,
    coalesce(nullif(btrim(benres_ip), ''), '0')::numeric(14,2)    as reported_ip_bene_resp,
    coalesce(nullif(btrim(pppymt_ip), ''), '0')::numeric(14,2)    as reported_ip_primary_payer,
    coalesce(nullif(btrim(medreimb_op), ''), '0')::numeric(14,2)  as reported_op_medicare_paid,
    coalesce(nullif(btrim(benres_op), ''), '0')::numeric(14,2)    as reported_op_bene_resp,
    coalesce(nullif(btrim(pppymt_op), ''), '0')::numeric(14,2)    as reported_op_primary_payer,
    coalesce(nullif(btrim(medreimb_car), ''), '0')::numeric(14,2) as reported_car_medicare_paid,
    coalesce(nullif(btrim(benres_car), ''), '0')::numeric(14,2)   as reported_car_bene_resp,
    coalesce(nullif(btrim(pppymt_car), ''), '0')::numeric(14,2)   as reported_car_primary_payer,
    _batch_id,
    _source_file,
    _source_row_num
from src
