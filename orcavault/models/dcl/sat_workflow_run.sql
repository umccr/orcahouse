{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail'
    )
}}

with ranked as (

    select
        sat.workflow_run_hk,
        sat.record_source,
        sat.workflow_name,
        sat.workflow_version,
        sat.state_status as workflow_run_status,
        min(sat.state_timestamp) over (partition by sat.workflow_run_hk) as workflow_run_start,
        max(sat.state_timestamp) over (partition by sat.workflow_run_hk) as workflow_run_end,
        coalesce(sat.state_comment, cmt.comment) as workflow_run_comment,
        row_number() over (partition by sat.workflow_run_hk order by sat.state_timestamp desc) as rank
    from
        {{ ref('sat_workflow_run_detail') }} sat
            full join {{ ref('sat_workflow_run_comment') }} cmt on cmt.workflow_run_hk = sat.workflow_run_hk
    {% if is_incremental() %}
    where
        sat.load_datetime > ( select coalesce(max(load_datetime), '1900-01-01') as ldts from {{ this }} )
    {% endif %}

),

source1 as (

    select
        workflow_run_hk,
        record_source,
        workflow_name,
        workflow_version,
        workflow_run_status,
        workflow_run_start,
        workflow_run_end,
        workflow_run_comment
    from
        ranked
    where
        rank = 1

),

source2 as (

    select
        workflow_run_hk,
        record_source,
        type_name as workflow_name,
        version as workflow_version,
        split_part(end_status, ';;', 1) as workflow_run_status,
        start_datetime as workflow_run_start,
        end_datetime as workflow_run_end,
        nullif(split_part(end_status, ';;', 2), '') as workflow_run_comment
    from
        {{ ref('sat_workflow_run_portal') }}
    {% if is_incremental() %}
    where
        load_datetime > ( select coalesce(max(load_datetime), '1900-01-01') as ldts from {{ this }} )
    {% endif %}

),

merged as (

    select * from source1
    union
    select * from source2

),

transformed as (

    select
        workflow_run_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        record_source,
        encode(sha256(concat(
            workflow_name,
            workflow_version,
            workflow_run_status,
            workflow_run_start,
            workflow_run_end
        )::bytea), 'hex') as hash_diff,
        workflow_name,
        workflow_version,
        workflow_run_status,
        workflow_run_start,
        workflow_run_end,
        workflow_run_comment
    from
        merged

),

final as (

    select
        cast(workflow_run_hk as char(64)) as workflow_run_hk,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(hash_diff as char(64)) as hash_diff,
        cast(workflow_name as varchar(255)) as workflow_name,
        cast(workflow_version as varchar(255)) as workflow_version,
        cast(workflow_run_status as varchar(255)) as workflow_run_status,
        cast(workflow_run_start as timestamptz) as workflow_run_start,
        cast(workflow_run_end as timestamptz) as workflow_run_end,
        cast(workflow_run_comment as text) as workflow_run_comment
    from
        transformed

)

select * from final
