{{
    config(
        indexes=[
            {'columns': ['portal_run_id'], 'type': 'btree'},
            {'columns': ['total_cost'], 'type': 'btree'},
            {'columns': ['compute_cost'], 'type': 'btree'},
            {'columns': ['license_cost'], 'type': 'btree'},
            {'columns': ['comment'], 'type': 'btree'},
            {'columns': ['ica_project'], 'type': 'btree'},
        ]
    )
}}

with source as (

    select
        hw.portal_run_id as portal_run_id,
        sat.total_cost as total_cost,
        sat.compute_cost as compute_cost,
        sat.license_cost as license_cost,
        sat.comment as comment,
        sat.ica_project as ica_project
    from
        {{ ref('hub_workflow_run') }} hw
		join {{ ref('sat_workflow_run_cost_ica') }} sat on hw.workflow_run_hk = sat.workflow_run_hk

),

final as (

    select
        cast(portal_run_id as char(16)) as portal_run_id,
        cast(total_cost as numeric(10,2)) as total_cost,
        cast(compute_cost as numeric(10,2)) as compute_cost,
        cast(license_cost as numeric(10,2)) as license_cost,
        cast(comment as text) as comment,
        cast(ica_project as varchar(255)) as ica_project
    from
        source
    order by portal_run_id desc nulls last

)

select * from final
