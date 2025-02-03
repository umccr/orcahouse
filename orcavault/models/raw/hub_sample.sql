{{ config(
    indexes=[
      {'columns': ['sample_id'], 'type': 'btree'},
    ]
)}}

with source as (

    select sample_id from {{ source('ods', 'data_portal_labmetadata') }}
    union
    select sample_id from {{ source('ods', 'data_portal_limsrow') }}
    union
    select sample_id from {{ source('ods', 'metadata_manager_sample') }}
    union
    select sample_id from {{ ref('spreadsheet_library_tracking_metadata') }}
    union
    select sample_id from {{ ref('spreadsheet_google_lims') }}

),

cleaned as (
    select * from source where sample_id is not null and sample_id <> ''
),

transformed as (

    select
        encode(sha256(cast(sample_id as bytea)), 'hex') as sample_hk,
        sample_id,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source
    from
        cleaned

),

final as (
    select * from transformed
)

select * from final
