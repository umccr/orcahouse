{{ config(
    indexes=[
      {'columns': ['library_id'], 'type': 'btree'},
    ]
)}}

with source as (

    select library_id from {{ source('ods', 'data_portal_labmetadata') }}
    union
    select library_id from {{ source('ods', 'data_portal_limsrow') }}
    union
    select library_id from {{ source('ods', 'metadata_manager_library') }}

),

cleaned as (
    select * from source where library_id is not null and library_id <> ''
),

transformed as (

    select
        encode(sha256(cast(library_id as bytea)), 'hex') as library_hk,
        library_id,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source
    from
        cleaned

),

final as (
    select * from transformed
)

select * from final
