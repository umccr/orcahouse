{{
    config(
        indexes=[
            {'columns': ['portal_run_id'], 'type': 'btree'},
            {'columns': ['load_datetime'], 'type': 'btree'},
            {'columns': ['last_seen_datetime'], 'type': 'btree'},
            {'columns': ['portal_run_id', 'last_seen_datetime'], 'type': 'btree'},
        ],
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='workflow_run_hk',
        merge_update_columns=['last_seen_datetime'],
        on_schema_change='fail'
    )
}}

with source1 as (

    select
        portal_run_id
    from
        {{ source('legacy', 'data_portal_workflow') }}
    {% if is_incremental() %}
    where
        cast(start as timestamptz) > ( select coalesce(max(load_datetime), '1900-01-01') as ldts from {{ this }} )
    {% endif %}

),

source2 as (

    select
        portal_run_id
    from {{ source('ods', 'workflow_manager_workflowrun') }} wfr
    {% if is_incremental() %}
        join {{ source('ods', 'workflow_manager_state') }} stt on stt.workflow_run_id = wfr.orcabus_id
    where
        cast(stt.timestamp as timestamptz) > ( select coalesce(max(load_datetime), '1900-01-01') as ldts from {{ this }} )
    {% endif %}

),

combined as (

    select distinct portal_run_id from source1
    union
    select distinct portal_run_id from source2

),

transformed as (

    select
        encode(sha256(cast(portal_run_id as bytea)), 'hex') as workflow_run_hk,
        portal_run_id,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'portal_workflow_manager') as record_source,
        cast('{{ run_started_at }}' as timestamptz) as last_seen_datetime
    from
        combined
    order by portal_run_id

),

final as (

    select
        cast(workflow_run_hk as char(64)) as workflow_run_hk,
        cast(portal_run_id as char(16)) as portal_run_id,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(last_seen_datetime as timestamptz) as last_seen_datetime
    from
        transformed

)

select * from final
