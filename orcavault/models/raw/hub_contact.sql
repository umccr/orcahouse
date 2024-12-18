{{ config(
    indexes=[
      {'columns': ['contact_id'], 'type': 'btree'},
    ]
)}}

with source as (

    select project_owner as contact_id from {{ source('ods', 'data_portal_labmetadata') }}
    union
    select project_owner as contact_id from {{ source('ods', 'data_portal_limsrow') }}
    union
    select contact_id from {{ source('ods', 'metadata_manager_contact') }}

),

cleaned as (
    select * from source where contact_id is not null and contact_id <> ''
),

transformed as (

    select
        encode(sha256(cast(contact_id as bytea)), 'hex') as contact_hk,
        contact_id,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source
    from
        cleaned

),

final as (
    select * from transformed
)

select * from final
