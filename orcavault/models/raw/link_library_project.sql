with source as (

    select library_id, project_name as project_id from {{ source('ods', 'data_portal_labmetadata') }}
    union
    select library_id, project_name as project_id from {{ source('ods', 'data_portal_limsrow') }}
    union
    select lib.library_id as library_id, prj.project_id as project_id from {{ source('ods', 'metadata_manager_library') }} as lib
        join {{ source('ods', 'metadata_manager_libraryprojectlink') }} as lnk on lnk.library_orcabus_id = lib.orcabus_id
        join {{ source('ods', 'metadata_manager_project') }} as prj on lnk.project_orcabus_id = prj.orcabus_id

),

cleaned as (

    select
        distinct library_id, project_id
    from
        source
    where
        (library_id is not null and library_id <> '') and
        (project_id is not null and project_id <> '')

),

transformed as (

    select
        encode(sha256(cast(project_id as bytea)), 'hex') as project_hk,
        encode(sha256(cast(library_id as bytea)), 'hex') as library_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source
    from
        cleaned

),

final as (

    select
        encode(sha256(concat(project_hk, library_hk)::bytea), 'hex') as library_project_hk,
        project_hk,
        library_hk,
        load_datetime,
        record_source
    from
        transformed

)

select * from final
