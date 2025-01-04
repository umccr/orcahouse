with source as (

    select project_name as project_id, project_owner as contact_id from {{ source('ods', 'data_portal_labmetadata') }}
    union
    select project_name as project_id, project_owner as contact_id from {{ source('ods', 'data_portal_limsrow') }}
    union
    select project_id, contact_id from {{ source('ods', 'metadata_manager_project') }} as prj
        join {{ source('ods', 'metadata_manager_projectcontactlink') }} as lnk on lnk.project_orcabus_id = prj.orcabus_id
        join {{ source('ods', 'metadata_manager_contact') }} as cnt on lnk.contact_orcabus_id = cnt.orcabus_id

),

cleaned as (

    select
        distinct trim(project_id) as project_id, trim(contact_id) as contact_id
    from
        source
    where
        (project_id is not null and project_id <> '') and
        (contact_id is not null and contact_id <> '')

),

transformed as (

    select
        encode(sha256(cast(contact_id as bytea)), 'hex') as contact_hk,
        encode(sha256(cast(project_id as bytea)), 'hex') as project_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source
    from
        cleaned

),

final as (

    select
        encode(sha256(concat(contact_hk, project_hk)::bytea), 'hex') as project_contact_hk,
        contact_hk,
        project_hk,
        load_datetime,
        record_source
    from
        transformed

)

select * from final
