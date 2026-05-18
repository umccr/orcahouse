{{
    config(
        indexes=[
            {'columns': ['portal_run_id'], 'type': 'btree'},
            {'columns': ['workflow_name'], 'type': 'btree'},
            {'columns': ['workflow_version'], 'type': 'btree'},
            {'columns': ['workflow_status'], 'type': 'btree'},
            {'columns': ['total_cost'], 'type': 'btree'},
            {'columns': ['compute_cost'], 'type': 'btree'},
            {'columns': ['license_cost'], 'type': 'btree'},
            {'columns': ['ica_project'], 'type': 'btree'},
        ]
    )
}}


with workflow as (

    select
        hub.workflow_run_hk as workflow_run_hk,
        hub.portal_run_id as portal_run_id,
        sat.workflow_name as workflow_name,
        sat.workflow_version as workflow_version,
        upper(sat.workflow_run_status) as workflow_run_status
    from {{ ref('hub_workflow_run') }} hub
        join {{ ref('sat_workflow_run') }} sat on sat.workflow_run_hk = hub.workflow_run_hk

),

cost as (

    SELECT 
        ica.workflow_run_hk as workflow_run_hk,
        case when ica.usage_context_type = 'Project' then ica.usage_context else NULL end as ica_project,
        SUM(cost) AS total_cost,
        SUM(cost) FILTER (WHERE ica.is_license_cost = 'false' and ica.category = 'Compute') AS compute_cost,
        SUM(cost) FILTER (WHERE ica.is_license_cost = 'true') AS license_cost
    FROM 
        {{ ref('sat_workflow_run_ica_usage') }} ica
    GROUP BY 
        workflow_run_hk, ica_project
    ORDER BY 
        workflow_run_hk

),


merged as (

    select
        workflow.portal_run_id as portal_run_id,
        workflow.workflow_name as workflow_name,
        workflow.workflow_version as workflow_version,
        workflow.workflow_run_status as workflow_status,
        cost.ica_project as ica_project,
        cost.total_cost as total_cost,
        cost.compute_cost as compute_cost,
        cost.license_cost as license_cost
    from cost
        inner join workflow on cost.workflow_run_hk = workflow.workflow_run_hk

),

final as (

    select
        cast(portal_run_id as char(16)) as portal_run_id,
        cast(workflow_name as varchar(255)) as workflow_name,
        cast(workflow_version as varchar(255)) as workflow_version,
        cast(workflow_status as varchar(255)) as workflow_status,
        cast(total_cost as numeric(10,2)) as total_cost,
        cast(compute_cost as numeric(10,2)) as compute_cost,
        cast(license_cost as numeric(10,2)) as license_cost,
        cast(ica_project as varchar(255)) as ica_project
    from
        merged
    order by portal_run_id desc nulls last

)

select * from final
