{{
    config(
        indexes=[
            {'columns': ['portal_run_id'], 'type': 'btree'},
            {'columns': ['library_id'], 'type': 'btree'},
            {'columns': ['portal_run_id', 'library_id'], 'type': 'btree'},
            {'columns': ['total_cost'], 'type': 'btree'},
            {'columns': ['compute_cost'], 'type': 'btree'},
            {'columns': ['license_cost'], 'type': 'btree'},
            {'columns': ['comment'], 'type': 'btree'},
            {'columns': ['ica_project'], 'type': 'btree'},
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

-- merged as (

--     select
-- 		sat.portal_run_id as portal_run_id,
-- 		sat.total_cost as total_cost,
-- 		sat.compute_cost as compute_cost,
-- 		sat.license_cost as license_cost,
-- 		sat.comment as comment,
-- 		sat.ica_project as ica_project
--     from {{ ref('hub_workflow_run') }} hub
--         join {{ ref('sat_workflow_run_cost_ica') }} sat on sat.workflow_run_hk = hub.workflow_run_hk

-- ),

transformed as (

    select
        linked.library_id as library_id,
        sat.portal_run_id as portal_run_id,
        sat.total_cost as total_cost,
        sat.compute_cost as compute_cost,
        sat.license_cost as license_cost,
        sat.comment as comment,
        sat.ica_project as ica_project
    from
        -- merged
		{{ ref('sat_workflow_run_cost_ica') }} sat
            join linked on linked.portal_run_id = sat.portal_run_id

),

final as (

    select
        cast(portal_run_id as char(16)) as portal_run_id,
        cast(library_id as varchar(255)) as library_id,
        cast(total_cost as numeric(10,2)) as total_cost,
        cast(compute_cost as numeric(10,2)) as compute_cost,
        cast(license_cost as numeric(10,2)) as license_cost,
        cast(comment as text) as comment,
        cast(ica_project as varchar(255)) as ica_project
    from
        transformed
    order by portal_run_id desc nulls last, library_id desc

)

select * from final
