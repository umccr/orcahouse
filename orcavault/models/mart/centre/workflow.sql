{{
    config(
        indexes=[
            {'columns': ['portal_run_id'], 'type': 'btree'},
            {'columns': ['library_id'], 'type': 'btree'},
            {'columns': ['portal_run_id', 'library_id'], 'type': 'btree'},
            {'columns': ['workflow_name'], 'type': 'btree'},
            {'columns': ['workflow_version'], 'type': 'btree'},
            {'columns': ['workflow_status'], 'type': 'btree'},
        ]
    )
}}

with linked as (

    select distinct
        hw.portal_run_id as portal_run_id,
        hl.library_id as library_id
    from {{ ref('hub_workflow_run') }} hw
        full join {{ ref('link_library_workflow_run') }} lnk on lnk.workflow_run_hk = hw.workflow_run_hk
        full join {{ ref('hub_library') }} hl on lnk.library_hk = hl.library_hk

),

ranked as (

    select
        workflow_run_hk,
        workflow_name,
        workflow_version,
        state_timestamp,
        state_status,
        row_number() over (partition by workflow_run_hk order by state_timestamp desc) as rank
    from {{ ref('sat_workflow_run_detail') }}

),

detailed as (

    select * from ranked where rank = 1

),

merged as (

    {# Potentially move this logic into DCL business vault. See https://github.com/umccr/orcahouse/pull/90 #}

    select
        hub.portal_run_id as portal_run_id,
        case
            when sat.workflow_name is null then
                ptl.type_name
            else
                sat.workflow_name
            end as workflow_name,
        case
            when sat.state_status is null then
                ptl.end_status
            else
                sat.state_status
            end as workflow_status,
        case
            when sat.workflow_version is null then
                ptl.version
            else
                sat.workflow_version
            end as workflow_version
    from {{ ref('hub_workflow_run') }} hub
        full join detailed sat on sat.workflow_run_hk = hub.workflow_run_hk
        full join {{ ref('sat_workflow_run_portal') }} ptl on ptl.workflow_run_hk = hub.workflow_run_hk

),

transformed as (

    select
        merged.portal_run_id as portal_run_id,
        merged.workflow_name as workflow_name,
        merged.workflow_version as workflow_version,
        merged.workflow_status as workflow_status,
        linked.library_id as library_id
    from
        merged
            join linked on linked.portal_run_id = merged.portal_run_id

),

final as (

    select
        cast(portal_run_id as char(16)) as portal_run_id,
        cast(library_id as varchar(255)) as library_id,
        cast(workflow_name as varchar(255)) as workflow_name,
        cast(workflow_version as varchar(255)) as workflow_version,
        cast(workflow_status as varchar(255)) as workflow_status
    from
        transformed
    order by portal_run_id desc nulls last, library_id desc

)

select * from final
