{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail'
    )
}}

with source as (

    select
        id,
        type_name,
        wfr_name,
        wfr_id,
        wfl_id,
        wfv_id,
        version,
        start as start_datetime,
        "end" as end_datetime,
        end_status,
        "input" as input_json,
        "output" as output_json,
        portal_run_id
    from
        {{ source('ods', 'data_portal_workflow') }}
    {% if is_incremental() %}
    where
        cast(start as timestamptz) > ( select coalesce(max(load_datetime), '1900-01-01') as ldts from {{ this }} )
    {% endif %}

),

transformed as (

    select
        encode(sha256(cast(portal_run_id as bytea)), 'hex') as workflow_run_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'data_portal_workflow') as record_source,
        encode(sha256(concat(
                id,
                type_name,
                wfr_name,
                wfr_id,
                wfl_id,
                wfv_id,
                version,
                start_datetime,
                end_datetime,
                end_status
        )::bytea), 'hex') as hash_diff,
        id,
        type_name,
        wfr_name,
        wfr_id,
        wfl_id,
        wfv_id,
        version,
        start_datetime,
        end_datetime,
        end_status,
        input_json,
        output_json
    from
        source

),

final as (

    select
        cast(workflow_run_hk as char(64)) as workflow_run_hk,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(hash_diff as char(64)) as hash_diff,
        cast(id as bigint) as id,
        cast(type_name as varchar(255)) as type_name,
        cast(wfr_name as text) as wfr_name,
        cast(wfr_id as varchar(255)) as wfr_id,
        cast(wfl_id as varchar(255)) as wfl_id,
        cast(wfv_id as varchar(255)) as wfv_id,
        cast(version as varchar(255)) as version,
        cast(start_datetime as timestamptz) as start_datetime,
        cast(end_datetime as timestamptz) as end_datetime,
        cast(end_status as varchar(255)) as end_status,
        cast(input_json as jsonb) as input_json,
        cast(output_json as jsonb) as output_json
    from
        transformed

)

select * from final
