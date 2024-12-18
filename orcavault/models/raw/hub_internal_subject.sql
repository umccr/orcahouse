{{ config(
    indexes=[
      {'columns': ['internal_subject_id'], 'type': 'btree'},
    ]
)}}

with source as (

    select subject_id as internal_subject_id from {{ source('ods', 'data_portal_labmetadata') }}
    union
    select subject_id as internal_subject_id from {{ source('ods', 'data_portal_limsrow') }}
    union
    select individual_id as internal_subject_id from {{ source('ods', 'metadata_manager_individual') }}

),

cleaned as (
    select * from source where internal_subject_id is not null and internal_subject_id <> ''
),

transformed as (

    select
        encode(sha256(cast(internal_subject_id as bytea)), 'hex') as internal_subject_hk,
        internal_subject_id,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source
    from
        cleaned

),

final as (
    select * from transformed
)

select * from final
