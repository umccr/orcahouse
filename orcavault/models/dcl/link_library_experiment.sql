{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key=['experiment_hk', 'library_hk'],
        on_schema_change='fail'
    )
}}

with source as (

    select library_id, experiment_id from {{ source('legacy', 'data_portal_labmetadata') }}
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

differentiated as (

    select
        encode(sha256(cast(experiment_id as bytea)), 'hex') as experiment_hk,
        encode(sha256(cast(library_id as bytea)), 'hex') as library_hk
    from
        cleaned
    {% if is_incremental() %}
    except
    select
        experiment_hk,
        library_hk
    from
        {{ this }}
    {% endif %}

),

transformed as (

    select
        experiment_hk,
        library_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source
    from
        differentiated

),

final as (

    select
        cast(encode(sha256(concat(experiment_hk, library_hk)::bytea), 'hex') as char(64)) as library_experiment_hk,
        cast(experiment_hk as char(64)) as experiment_hk,
        cast(library_hk as char(64)) as library_hk,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source
    from
        transformed

)

select * from final
