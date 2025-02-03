{{ config(
    indexes=[
      {'columns': ['external_subject_id'], 'type': 'btree'},
    ]
)}}

with source as (

    select external_subject_id from {{ source('ods', 'data_portal_labmetadata') }}
    union
    select external_subject_id from {{ source('ods', 'data_portal_limsrow') }}
    union
    select subject_id as external_subject_id from {{ source('ods', 'metadata_manager_subject') }}
    union
    select external_subject_id from {{ ref('spreadsheet_library_tracking_metadata') }}
    union
    select external_subject_id from {{ ref('spreadsheet_google_lims') }}

),

cleaned as (
    select * from source where external_subject_id is not null and external_subject_id <> ''
),

transformed as (

    select
        encode(sha256(cast(external_subject_id as bytea)), 'hex') as external_subject_hk,
        external_subject_id,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source
    from
        cleaned

),

final as (
    select * from transformed
)

select * from final
