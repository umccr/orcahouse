{{
    config(
        indexes=[
            {'columns': ['library_id'], 'type': 'btree'},
            {'columns': ['load_datetime'], 'type': 'btree'},
            {'columns': ['last_seen_datetime'], 'type': 'btree'},
            {'columns': ['library_id', 'last_seen_datetime'], 'type': 'btree'},
        ],
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='library_hk',
        merge_update_columns=['last_seen_datetime'],
        on_schema_change='fail'
    )
}}

with source as (

    select library_id from {{ source('legacy', 'data_portal_labmetadata') }}
    union
    select library_id from {{ source('legacy', 'data_portal_limsrow') }}
    union
    select library_id from {{ source('ods', 'metadata_manager_library') }}
    union
    select library_id from {{ ref('spreadsheet_library_tracking_metadata') }}
    union
    select library_id from {{ ref('spreadsheet_google_lims') }}

),

cleaned as (

    select * from source where library_id is not null and library_id <> ''

),

differentiated as (

    select library_id from cleaned
    {% if is_incremental() %}
    except
    select library_id from {{ this }}
    {% endif %}

),

transformed as (

    select
        encode(sha256(cast(library_id as bytea)), 'hex') as library_hk,
        library_id,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source,
        cast('{{ run_started_at }}' as timestamptz) as last_seen_datetime
    from
        differentiated

),

final as (

    select
        cast(library_hk as char(64)) as library_hk,
        cast(library_id as varchar(255)) as library_id,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(last_seen_datetime as timestamptz) as last_seen_datetime
    from
        transformed

)

select * from final
