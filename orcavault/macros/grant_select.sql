{% macro grant_select(role) %}
{% set sql %}
    GRANT USAGE ON SCHEMA mart TO {{ role }};
    GRANT SELECT ON ALL tables IN SCHEMA mart TO {{ role }};

    {# FIXME to be finalised - experimental alias views on public schema for AppSync GraphQL introspection purpose #}
    CREATE VIEW public.lims as SELECT * FROM mart.lims;
    CREATE VIEW public.fastq as SELECT * FROM mart.fastq;
    CREATE VIEW public.fastq_history as SELECT * FROM mart.fastq_history;
    GRANT USAGE ON SCHEMA public TO {{ role }};
    GRANT SELECT ON ALL tables IN SCHEMA public TO {{ role }};
{% endset %}

{% do run_query(sql) %}
{% do log("Privileges granted", info=True) %}
{% endmacro %}
