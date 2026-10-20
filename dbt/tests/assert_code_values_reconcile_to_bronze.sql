-- Reconciliation of code VALUES, counted straight from bronze (independent of the models):
--   non-null code values on non-orphan segments
--   = claim_diagnosis rows + claim_procedure rows + code_exception rows
-- Proves every diagnosis/procedure value landed in exactly one place.
{%- set dx = ['admtng_icd9_dgns_cd'] %}
{%- for i in range(1, 11) %}{% do dx.append('icd9_dgns_cd_' ~ i) %}{% endfor %}
{%- set px = [] %}
{%- for i in range(1, 7) %}{% do px.append('icd9_prcdr_cd_' ~ i) %}{% endfor %}
{%- set hc = [] %}
{%- for i in range(1, 46) %}{% do hc.append('hcpcs_cd_' ~ i) %}{% endfor %}


with ip as (
    select {{ count_non_blank(dx + px + hc) }} as n
    from {{ source('bronze', 'desynpuf_inpatient') }} b
    where not exists (select 1 from {{ ref('claim_exception') }} q
                      where q.source_table = 'bronze.desynpuf_inpatient'
                        and q._source_row_num = b._source_row_num)
),
op as (   -- outpatient ICD-9 procedure columns are not mapped (F6)
    select {{ count_non_blank(dx + hc) }} as n
    from {{ source('bronze', 'desynpuf_outpatient') }} b
    where not exists (select 1 from {{ ref('claim_exception') }} q
                      where q.source_table = 'bronze.desynpuf_outpatient'
                        and q._source_row_num = b._source_row_num)
),
totals as (
    select
        (select n from ip) + (select n from op)              as bronze_values,
        (select count(*) from {{ ref('claim_diagnosis') }} where source_system = 'DESYNPUF')
      + (select count(*) from {{ ref('claim_procedure') }} where source_system = 'DESYNPUF')
      + (select count(*) from {{ ref('code_exception') }} where source_system = 'DESYNPUF')   as silver_plus_quarantine_values
)
select * from totals where bronze_values <> silver_plus_quarantine_values
