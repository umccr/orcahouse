{{ config(
    indexes=[
      {'columns': ['external_sample_id'], 'type': 'btree'},
    ]
)}}

with source as (

    select external_sample_id from {{ source('ods', 'data_portal_labmetadata') }}
    union
    select external_sample_id from {{ source('ods', 'data_portal_limsrow') }}
    union
    select external_sample_id from {{ source('ods', 'metadata_manager_sample') }}

),

cleaned as (
    select * from source where external_sample_id is not null and external_sample_id <> ''
),

transformed as (

    select
        encode(sha256(cast(external_sample_id as bytea)), 'hex') as external_sample_hk,
        external_sample_id,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source
    from
        cleaned

),

final as (
    select * from transformed
)

select * from final
