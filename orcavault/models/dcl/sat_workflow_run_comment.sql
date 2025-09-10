{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail'
    )
}}

with source as (

    select
        wfr.portal_run_id as portal_run_id,
        cmt.orcabus_id as orcabus_id,
        cmt.comment as comment,
        cmt.created_at as created_at,
        cmt.created_by as created_by,
        cmt.updated_at as updated_at,
        cmt.is_deleted as is_deleted
    from {{ source('ods', 'workflow_manager_workflowrun') }} wfr
        join {{ source('ods', 'workflow_manager_workflowruncomment') }} cmt on cmt.workflow_run_id = wfr.orcabus_id
    {% if is_incremental() %}
    where
        cast(cmt.created_at as timestamptz) > ( select coalesce(max(load_datetime), '1900-01-01') as ldts from {{ ref('hub_workflow_run') }} )
    {% endif %}

),

transformed as (

    select
        encode(sha256(cast(portal_run_id as bytea)), 'hex') as workflow_run_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'workflow_manager_workflowruncomment') as record_source,
        encode(sha256(concat(
            orcabus_id,
            comment,
            created_at,
            created_by,
            updated_at,
            is_deleted
        )::bytea), 'hex') as hash_diff,
        orcabus_id,
        comment,
        created_at,
        created_by,
        updated_at,
        is_deleted
    from
        source

),

final as (

    select
        cast(workflow_run_hk as char(64)) as workflow_run_hk,
        cast(hash_diff as char(64)) as workflow_run_sq,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(hash_diff as char(64)) as hash_diff,
        cast(orcabus_id as char(26)) as orcabus_id,
        cast(comment as text) as comment,
        cast(created_at as timestamptz) as created_at,
        cast(created_by as varchar(255)) as created_by,
        cast(updated_at as timestamptz) as updated_at,
        cast(is_deleted as boolean) as is_deleted
    from
        transformed

)

select * from final
