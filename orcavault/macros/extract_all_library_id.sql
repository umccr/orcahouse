{#
    Use Case:
    The intent is to do data mining the well-known library_id pattern from the path more globally.
    Note the regexp_matches() function used. It return all matching rows.
    https://www.google.com/search?q=postgresql+regexp_matches+vs+regexp_match
#}

{% macro extract_all_library_id(column_name) %}

    (regexp_matches({{ column_name }}, '(?:L\d{7}|L(?:PRJ|CCR|MDX|TGX)\d{6}|Undetermined)', 'g'))[1]

{% endmacro %}
