{{
    config(
        indexes=[
            {'columns': ['external_sample_id'], 'type': 'btree'},
            {'columns': ['load_datetime'], 'type': 'btree'},
            {'columns': ['last_seen_datetime'], 'type': 'btree'},
            {'columns': ['external_sample_id', 'last_seen_datetime'], 'type': 'btree'},
        ],
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='external_sample_hk',
        merge_update_columns=['last_seen_datetime'],
        on_schema_change='fail'
    )
}}

with source as (

    select external_sample_id from {{ source('legacy', 'data_portal_labmetadata') }}
    union
    select external_sample_id from {{ source('legacy', 'data_portal_limsrow') }}
    union
    select external_sample_id from {{ source('ods', 'metadata_manager_sample') }}
    union
    select external_sample_id from {{ ref('spreadsheet_library_tracking_metadata') }}
    union
    select external_sample_id from {{ ref('spreadsheet_google_lims') }}

),

cleaned as (

    select * from source where external_sample_id is not null and external_sample_id <> ''

),

differentiated as (

    select external_sample_id from cleaned
    {% if is_incremental() %}
    except
    select external_sample_id from {{ this }}
    {% endif %}

),

transformed as (

    select
        encode(sha256(cast(external_sample_id as bytea)), 'hex') as external_sample_hk,
        external_sample_id,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source,
        cast('{{ run_started_at }}' as timestamptz) as last_seen_datetime
    from
        differentiated

),

final as (

    select
        cast(external_sample_hk as char(64)) as external_sample_hk,
        cast(external_sample_id as varchar(255)) as external_sample_id,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(last_seen_datetime as timestamptz) as last_seen_datetime
    from
        transformed

)

select * from final
