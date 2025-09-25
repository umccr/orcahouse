{{
    config(
        indexes=[
            {'columns': ['library_id'], 'type': 'btree'},
            {'columns': ['metadata_manager'], 'type': 'btree'},
            {'columns': ['workflow_manager'], 'type': 'btree'},
            {'columns': ['sequence_run_manager'], 'type': 'btree'},
        ]
    )
}}

with mm_unique_libraries as (

    select distinct library_id from {{ source('ods', 'metadata_manager_library') }}

),

wfm_unique_libraries as (

    select distinct library_id from {{ source('ods', 'workflow_manager_library') }}

),

srm_unique_libraries as (

    select distinct library_id from {{ source('ods', 'sequence_run_manager_libraryassociation') }}

),

transformed as (

    select
        hub.library_id as library_id,
        case when mm.library_id is not null then 1 else 0 end metadata_manager,
        case when wfm.library_id is not null then 1 else 0 end workflow_manager,
        case when srm.library_id is not null then 1 else 0 end sequence_run_manager
    from {{ ref('hub_library') }} hub
        left join mm_unique_libraries mm on hub.library_id = mm.library_id
        left join wfm_unique_libraries wfm on hub.library_id = wfm.library_id
        left join srm_unique_libraries srm on hub.library_id = srm.library_id

),

final as (

    select
        cast(library_id as varchar(255)) as library_id,
        cast(metadata_manager as smallint) as metadata_manager,
        cast(workflow_manager as smallint) as workflow_manager,
        cast(sequence_run_manager as smallint) as sequence_run_manager
    from
        transformed
    order by library_id desc

)

select * from final
