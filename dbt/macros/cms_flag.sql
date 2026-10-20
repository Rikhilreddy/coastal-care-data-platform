{#- CMS chronic-condition flags: 1 = yes, 2 = no. Anything else becomes NULL and is caught by tests. -#}
{% macro cms_flag(col) -%}
    case btrim({{ col }}) when '1' then true when '2' then false end
{%- endmacro %}
