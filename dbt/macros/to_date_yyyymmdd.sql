{#- Convert a YYYYMMDD text value to DATE; blanks become NULL. -#}
{% macro to_date_yyyymmdd(col) -%}
    to_date(nullif(btrim({{ col }}), ''), 'YYYYMMDD')
{%- endmacro %}
