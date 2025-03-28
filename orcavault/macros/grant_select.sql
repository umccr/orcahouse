{% macro grant_select(role) %}
{% set sql %}
    GRANT USAGE ON SCHEMA mart TO {{ role }};
    GRANT SELECT ON ALL tables IN SCHEMA mart TO {{ role }};
{% endset %}

{% do run_query(sql) %}
{% do log("Privileges granted", info=True) %}
{% endmacro %}
