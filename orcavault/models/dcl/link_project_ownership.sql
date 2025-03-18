{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key=['owner_hk', 'project_hk'],
        on_schema_change='fail'
    )
}}

with source as (

    select project_name as project_id, project_owner as owner_id from {{ source('ods', 'data_portal_labmetadata') }}
    union
    select project_name as project_id, project_owner as owner_id from {{ source('ods', 'data_portal_limsrow') }}
    union
    select project_id, contact_id as owner_id from {{ source('ods', 'metadata_manager_project') }} as prj
        join {{ source('ods', 'metadata_manager_projectcontactlink') }} as lnk on lnk.project_orcabus_id = prj.orcabus_id
        join {{ source('ods', 'metadata_manager_contact') }} as cnt on lnk.contact_orcabus_id = cnt.orcabus_id
    union
    select project_name as project_id, project_owner as owner_id from {{ ref('spreadsheet_library_tracking_metadata') }}
    union
    select project_name as project_id, project_owner as owner_id from {{ ref('spreadsheet_google_lims') }}

),

cleaned as (

    select
        distinct trim(project_id) as project_id, trim(owner_id) as owner_id
    from
        source
    where
        (project_id is not null and project_id <> '') and
        (owner_id is not null and owner_id <> '')

),

differentiated as (

    select
        encode(sha256(cast(owner_id as bytea)), 'hex') as owner_hk,
        encode(sha256(cast(project_id as bytea)), 'hex') as project_hk
    from
        cleaned
    {% if is_incremental() %}
    except
    select
        owner_hk,
        project_hk
    from
        {{ this }}
    {% endif %}

),

transformed as (

    select
        owner_hk,
        project_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source
    from
        differentiated

),

final as (

    select
        cast(encode(sha256(concat(owner_hk, project_hk)::bytea), 'hex') as char(64)) as project_owner_hk,
        cast(owner_hk as char(64)) as owner_hk,
        cast(project_hk as char(64)) as project_hk,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source
    from
        transformed

)

select * from final
