{#
    Use Case:
    The intent is to do data mining the well-known library_id pattern from analysis data output path.
    It return single match or NULL otherwise.
#}

{% macro extract_library_id(column_name) %}

    (regexp_match({{ column_name }}, '(?:L\d{7}|L(?:PRJ|CCR|MDX|TGX)\d{6})'))[1]

{% endmacro %}
