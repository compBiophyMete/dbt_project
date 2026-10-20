{#
    Use a model's custom schema (+schema) as-is, without dbt's default
    "<target schema>_" prefix, so staging lands in `stg_pipedrive` rather
    than `public_stg_pipedrive`.

    Applies to this project's models only. Package models (Elementary) keep
    dbt's default prefixing: the Elementary CLI profile reads its results from
    `<target schema>_elementary`.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- elif node.package_name == project_name -%}
        {{ custom_schema_name | trim }}
    {%- else -%}
        {{ target.schema }}_{{ custom_schema_name | trim }}
    {%- endif -%}

{%- endmacro %}
