with source as (

    select library_id, experiment_id from {{ source('ods', 'data_portal_labmetadata') }}
    union
    select library_id, experiment_id from {{ ref('spreadsheet_library_tracking_metadata') }}

),

cleaned as (

    select
        distinct library_id, experiment_id
    from
        source
    where
        (library_id is not null and library_id <> '') and
        (experiment_id is not null and experiment_id <> '')

),

transformed as (

    select
        encode(sha256(cast(experiment_id as bytea)), 'hex') as experiment_hk,
        encode(sha256(cast(library_id as bytea)), 'hex') as library_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source
    from
        cleaned

),

final as (

    select
        encode(sha256(concat(experiment_hk, library_hk)::bytea), 'hex') as library_experiment_hk,
        experiment_hk,
        library_hk,
        load_datetime,
        record_source
    from
        transformed

)

select * from final
