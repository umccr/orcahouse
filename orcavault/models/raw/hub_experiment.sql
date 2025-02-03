{{ config(
    indexes=[
      {'columns': ['experiment_id'], 'type': 'btree'},
    ]
)}}

with source as (

    select experiment_id from {{ source('ods', 'data_portal_labmetadata') }}
    union
    select experiment_id from {{ ref('spreadsheet_library_tracking_metadata') }}

),

cleaned as (
    select
        distinct trim(experiment_id) as experiment_id
    from
        source
    where
        experiment_id is not null and experiment_id <> ''
),

transformed as (

    select
        encode(sha256(cast(experiment_id as bytea)), 'hex') as experiment_hk,
        experiment_id,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source
    from
        cleaned

),

final as (
    select * from transformed
)

select * from final
