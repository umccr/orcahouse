{{
    config(
        indexes=[
            {'columns': ['base_portal_run_id'], 'type': 'btree'},
            {'columns': ['alias_portal_run_id'], 'type': 'btree'},
        ],
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='sal_workflow_run_hk',
        on_schema_change='fail'
    )
}}

with source as (

    select
        *
    from
        {{ ref('mdm__workflow_run') }}
    {% if is_incremental() %}
    where
        ( select count(1) from {{ ref('mdm__workflow_run') }} ) > 0
    {% endif %}

),

transformed as (

    select
        encode(sha256(cast(base_portal_run_id as bytea)), 'hex') as base_workflow_run_hk,
        encode(sha256(cast(alias_portal_run_id as bytea)), 'hex') as alias_workflow_run_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        'mdm__workflow_run' as record_source,
        base_portal_run_id,
        alias_portal_run_id
    from
        source

),

final as (

    select
        cast(encode(sha256(concat(base_workflow_run_hk, alias_workflow_run_hk)::bytea), 'hex') as char(64)) as sal_workflow_run_hk,
        cast(base_workflow_run_hk as char(64)) as base_workflow_run_hk,
        cast(alias_workflow_run_hk as char(64)) as alias_workflow_run_hk,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(base_portal_run_id as char(16)) as base_portal_run_id,
        cast(alias_portal_run_id as char(16)) as alias_portal_run_id
    from
        transformed

)

select * from final
