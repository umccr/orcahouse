{% macro extract_sequencing_run_id(column_name) %}

    (regexp_match({{ column_name }}, '(?:/)((\d{6}|\d{8})_(A\d{5}|LH\d{5})_\d{4}_[A-Z0-9]{10})(?:/)'))[1]

{% endmacro %}
