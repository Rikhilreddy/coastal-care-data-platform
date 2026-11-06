{% macro line_of_business(payer_col) -%}
case
    when {{ payer_col }} ilike '%dual%'        then 'DUAL'
    when {{ payer_col }} ilike '%medicare%'    then 'MEDICARE'
    when {{ payer_col }} ilike '%medicaid%'    then 'MEDICAID'
    when {{ payer_col }} = 'NO_INSURANCE' or {{ payer_col }} is null then 'SELF_PAY'
    else 'COMMERCIAL'
end
{%- endmacro %}
