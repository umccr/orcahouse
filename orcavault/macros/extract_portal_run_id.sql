{% macro extract_portal_run_id(column_name) %}

    (regexp_match({{ column_name }}, '(?:/)(\d{8}[a-zA-Z0-9]{8})(?:/)'))[1]

{% endmacro %}
