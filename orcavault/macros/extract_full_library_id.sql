{#
    Use Case:
    The intent is to do data mining the well-known library_id pattern from primary data output path.
    It return single match or NULL otherwise. Include the 'Undetermined' as expected for typical bcl_convert output.
#}

{% macro extract_full_library_id(column_name) %}

    (regexp_match({{ column_name }}, '(?:L\d{7}|L(?:PRJ|CCR|MDX|TGX)\d{6}|Undetermined)'))[1]

{% endmacro %}
