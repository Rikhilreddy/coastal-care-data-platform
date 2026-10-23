{#- Canonical silver.claim_diagnosis columns; each source's int model must provide them. -#}
{% macro claim_diagnosis_columns() -%}
    source_system, claim_id, claim_type, segment, dx_position, dx_role,
    source_code_system, source_code, icd10_code, conversion_method, conversion_decided_by,
    icd10_billable, is_sensitive, source_table, _source_row_num
{%- endmacro %}
