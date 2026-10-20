{#- Use the configured schema name exactly (silver, gold) instead of dbt's default
    "<target_schema>_<custom_schema>" naming, so models land in the medallion schemas. -#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}{{ target.schema }}{%- else -%}{{ custom_schema_name | trim }}{%- endif -%}
{%- endmacro %}
