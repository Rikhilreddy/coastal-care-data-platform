{#- Sum of non-blank values across a list of columns, e.g. for counting code values in wide tables. -#}
{% macro count_non_blank(cols) -%}
    {% for c in cols %}count(nullif(btrim({{ c }}), '')){{ ' + ' if not loop.last }}{% endfor %}
{%- endmacro %}
