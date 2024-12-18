{{ config(
    indexes=[
      {'columns': ['project_id'], 'type': 'btree'},
    ]
)}}

with source as (

    select project_name as project_id from {{ source('ods', 'data_portal_labmetadata') }}
    union
    select project_name as project_id from {{ source('ods', 'data_portal_limsrow') }}
    union
    select project_id from {{ source('ods', 'metadata_manager_project') }}

),

cleaned as (
    select * from source where project_id is not null and project_id <> ''
),

transformed as (

    select
        encode(sha256(cast(project_id as bytea)), 'hex') as project_hk,
        project_id,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source
    from
        cleaned

),

final as (
    select * from transformed
)

select * from final
