{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='library_workflow_run_hk',
        on_schema_change='fail'
    )
}}

with source1 as (

    select
        wfr.portal_run_id as portal_run_id,
        lbr.library_id as library_id
    from {{ source('ods', 'data_portal_workflow') }} wfr
        join {{ source('ods', 'data_portal_libraryrun_workflows') }} lnk on lnk.workflow_id = wfr.id
        join {{ source('ods', 'data_portal_libraryrun') }} lbr on lnk.libraryrun_id = lbr.id
    {% if is_incremental() %}
    where
        cast(start as timestamptz) > ( select coalesce(max(load_datetime), '1900-01-01') as ldts from {{ this }} )
    {% endif %}

),

source2 as (

    select
        wfr.portal_run_id as portal_run_id,
        lib.library_id as library_id
    from {{ source('ods', 'workflow_manager_workflowrun') }} wfr
        join {{ source('ods', 'workflow_manager_libraryassociation') }} lnk on lnk.workflow_run_id = wfr.orcabus_id
        join {{ source('ods', 'workflow_manager_library') }} lib on lnk.library_id = lib.orcabus_id
    {% if is_incremental() %}
    where
        cast(lnk.association_date as timestamptz) > ( select coalesce(max(load_datetime), '1900-01-01') as ldts from {{ this }} )
    {% endif %}

),

combined as (

    select distinct portal_run_id, library_id from source1
    union
    select distinct portal_run_id, library_id from source2

),

encoded as (

    select
        encode(sha256(cast(portal_run_id as bytea)), 'hex') as workflow_run_hk,
        encode(sha256(cast(library_id as bytea)), 'hex') as library_hk
    from
        combined

),

transformed as (

    select
        cast(encode(sha256(concat(workflow_run_hk, library_hk)::bytea), 'hex') as char(64)) as library_workflow_run_hk,
        workflow_run_hk,
        library_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'portal_workflow_manager') as record_source
    from
        encoded

),

final as (

    select
        cast(library_workflow_run_hk as char(64)) as library_workflow_run_hk,
        cast(workflow_run_hk as char(64)) as workflow_run_hk,
        cast(library_hk as char(64)) as library_hk,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source
    from
        transformed

)

select * from final
