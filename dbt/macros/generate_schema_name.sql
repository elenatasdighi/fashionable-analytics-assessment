{#
    Override dbt's default generate_schema_name so that `+schema: staging` in
    dbt_project.yml produces a schema literally called `staging` rather than
    the default `<target_schema>_staging` (e.g. `main_staging`).

    Falls back to target.schema for models without a custom schema config.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
