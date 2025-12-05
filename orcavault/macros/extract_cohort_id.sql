{% macro extract_cohort_id(column_name) %}

    (regexp_match({{ column_name }}, '(?<=byob-icav2\/).+?(?=\/)'))[1]

{% endmacro %}
