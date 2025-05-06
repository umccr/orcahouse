{% macro grant_select(role) %}
{% set sql %}
    {# role is passed by dbt run exec via ECS task env var at infra deploy time. See infra/ecs/orcavault-dbt/main.tf #}
    GRANT USAGE ON SCHEMA mart TO {{ role }};
    GRANT SELECT ON ALL tables IN SCHEMA mart TO {{ role }};

    {# FIXME to be finalised - experimental alias views on public schema for AppSync GraphQL introspection purpose #}
    CREATE VIEW public.lims as SELECT * FROM mart.lims;
    CREATE VIEW public.fastq as SELECT * FROM mart.fastq;
    CREATE VIEW public.fastq_history as SELECT * FROM mart.fastq_history;
    CREATE VIEW public.bam as SELECT * FROM mart.bam;
    CREATE VIEW public.workflow as SELECT * FROM mart.workflow;
    GRANT USAGE ON SCHEMA public TO {{ role }};
    GRANT SELECT ON ALL tables IN SCHEMA public TO {{ role }};
{% endset %}

{% do run_query(sql) %}
{% do log("Privileges granted", info=True) %}
{% endmacro %}
