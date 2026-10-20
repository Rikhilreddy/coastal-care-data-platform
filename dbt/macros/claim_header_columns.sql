{#- The canonical silver.claim_header column list. Every source's int_*__claim_header model
    must produce these columns; claim_header.sql selects them BY NAME from each source,
    so a column added in one source but not another fails loudly instead of shifting data. -#}
{% macro claim_header_columns() -%}
    source_system, claim_id, claim_type, source_claim_type, payer_name, member_source_id,
    segment_count, claim_from_date, claim_thru_date, claim_year, admission_date, discharge_date,
    provider_id, attending_npi, operating_npi, other_npi, drg_code, utilization_days,
    billed_amount, paid_amount, primary_payer_paid_amount, pass_thru_per_diem_amount,
    ip_deductible_amount, part_a_coinsurance_amount, blood_deductible_amount,
    part_b_deductible_amount, part_b_coinsurance_amount, is_adjustment, primary_dx_missing,
    source_table, _batch_id, _source_file, _source_row_nums
{%- endmacro %}
