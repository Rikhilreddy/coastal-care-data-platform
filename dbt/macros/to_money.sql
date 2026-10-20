{#- Convert a text dollar amount to NUMERIC(14,2); blanks become NULL. Negatives are kept (F2). -#}
{% macro to_money(col) -%}
    nullif(btrim({{ col }}), '')::numeric(14,2)
{%- endmacro %}
