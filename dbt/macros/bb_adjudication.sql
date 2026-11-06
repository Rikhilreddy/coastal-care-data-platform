{#- Amount of one Blue Button adjudication category on a FHIR EOB item, rounded to cents (H17). -#}
{% macro bb_adjudication(item, category) -%}
round(coalesce((jsonb_path_query_first({{ item }}, '$.adjudication[*] ? (@.category.coding[0].code == "https://bluebutton.cms.gov/resources/variables/{{ category }}").amount.value') #>> '{}')::numeric, 0), 2)
{%- endmacro %}
