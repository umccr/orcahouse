{{
    config(
        indexes=[
            {'columns': ['experiment_id'], 'type': 'btree'},
            {'columns': ['load_datetime'], 'type': 'btree'},
            {'columns': ['last_seen_datetime'], 'type': 'btree'},
            {'columns': ['experiment_id', 'last_seen_datetime'], 'type': 'btree'},
        ],
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='experiment_hk',
        merge_update_columns=['last_seen_datetime'],
        on_schema_change='fail'
    )
}}

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

differentiated as (

    select experiment_id from cleaned
    {% if is_incremental() %}
    except
    select experiment_id from {{ this }}
    {% endif %}

),

transformed as (

    select
        encode(sha256(cast(experiment_id as bytea)), 'hex') as experiment_hk,
        experiment_id,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source,
        cast('{{ run_started_at }}' as timestamptz) as last_seen_datetime
    from
        differentiated

),

final as (

    select
        cast(experiment_hk as char(64)) as experiment_hk,
        cast(experiment_id as varchar(255)) as experiment_id,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(last_seen_datetime as timestamptz) as last_seen_datetime
    from
        transformed

)

select * from final
