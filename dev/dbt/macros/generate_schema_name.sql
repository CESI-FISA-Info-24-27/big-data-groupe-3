{% macro generate_schema_name(custom_schema_name, node) -%}

    {#- Utiliser les tags pour déterminer le schéma #}
    {%- if 'staging' in node.tags -%}
        staging
    {%- elif 'ods' in node.tags or 'core' in node.tags -%}
        ods
    {%- elif 'dimension' in node.tags or 'fact' in node.tags -%}
        dwh
    {%- elif 'datamart' in node.tags -%}
        datamart
    {%- elif custom_schema_name is not none -%}
        {{ custom_schema_name }}
    {%- else -%}
        {{ target.schema }}
    {%- endif -%}

{%- endmacro %}
