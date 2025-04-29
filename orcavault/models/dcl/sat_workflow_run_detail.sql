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
        wfr.orcabus_id as workflow_run_orcabus_id,
        wfr.execution_id as workflow_run_execution_id,
        wfr.workflow_run_name as workflow_run_name,
        wfr.comment as workflow_run_comment,
        wfl.orcabus_id as workflow_orcabus_id,
        wfl.workflow_name as workflow_name,
        wfl.workflow_version as workflow_version,
        wfl.execution_engine as workflow_execution_engine,
        wfl.execution_engine_pipeline_id as workflow_execution_engine_pipeline_id,
        stt.orcabus_id as state_orcabus_id,
        stt.status as state_status,
        stt.timestamp as state_timestamp,
        stt.comment as state_comment,
        pld.orcabus_id as payload_orcabus_id,
        pld.payload_ref_id as payload_ref_id,
        pld.version as payload_version,
        pld.data as payload_data
    from {{ source('ods', 'workflow_manager_workflowrun') }} wfr
        join {{ source('ods', 'workflow_manager_workflow') }} wfl on wfl.orcabus_id = wfr.workflow_id
        full join {{ source('ods', 'workflow_manager_state') }} stt on stt.workflow_run_id = wfr.orcabus_id
        full join {{ source('ods', 'workflow_manager_payload') }} pld on pld.orcabus_id = stt.payload_id
    {% if is_incremental() %}
    where
        cast(stt.timestamp as timestamptz) > ( select coalesce(max(load_datetime), '1900-01-01') as ldts from {{ this }} )
    {% endif %}

),

transformed as (

    select
        encode(sha256(cast(portal_run_id as bytea)), 'hex') as workflow_run_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'workflow_manager') as record_source,
        encode(sha256(concat(
            workflow_run_orcabus_id,
            workflow_run_execution_id,
            workflow_run_name,
            workflow_run_comment,
            workflow_orcabus_id,
            workflow_name,
            workflow_version,
            workflow_execution_engine,
            workflow_execution_engine_pipeline_id,
            state_orcabus_id,
            state_status,
            state_timestamp,
            state_comment,
            payload_orcabus_id,
            payload_ref_id,
            payload_version
        )::bytea), 'hex') as hash_diff,
        workflow_run_orcabus_id,
        workflow_run_execution_id,
        workflow_run_name,
        workflow_run_comment,
        workflow_orcabus_id,
        workflow_name,
        workflow_version,
        workflow_execution_engine,
        workflow_execution_engine_pipeline_id,
        state_orcabus_id,
        state_status,
        state_timestamp,
        state_comment,
        payload_orcabus_id,
        payload_ref_id,
        payload_version,
        payload_data
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
        cast(workflow_run_orcabus_id as char(26)) as workflow_run_orcabus_id,
        cast(workflow_run_execution_id as varchar(255)) as workflow_run_execution_id,
        cast(workflow_run_name as varchar(255)) as workflow_run_name,
        cast(workflow_run_comment as varchar(255)) as workflow_run_comment,
        cast(workflow_orcabus_id as char(26)) as workflow_orcabus_id,
        cast(workflow_name as varchar(255)) as workflow_name,
        cast(workflow_version as varchar(255)) as workflow_version,
        cast(workflow_execution_engine as varchar(255)) as workflow_execution_engine,
        cast(workflow_execution_engine_pipeline_id as varchar(255)) as workflow_execution_engine_pipeline_id,
        cast(state_orcabus_id as varchar(26)) as state_orcabus_id,
        cast(state_status as varchar(255)) as state_status,
        cast(state_timestamp as timestamptz) as state_timestamp,
        cast(state_comment as varchar(255)) as state_comment,
        cast(payload_orcabus_id as char(26)) as payload_orcabus_id,
        cast(payload_ref_id as varchar(255)) as payload_ref_id,
        cast(payload_version as varchar(255)) as payload_version,
        cast(payload_data as jsonb) as payload_data
    from
        transformed

)

select * from final
