{{
    config(
        indexes=[
            {'columns': ['external_subject_id'], 'type': 'btree'},
            {'columns': ['load_datetime'], 'type': 'btree'},
            {'columns': ['last_seen_datetime'], 'type': 'btree'},
            {'columns': ['external_subject_id', 'last_seen_datetime'], 'type': 'btree'},
        ],
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='external_subject_hk',
        merge_update_columns=['last_seen_datetime'],
        on_schema_change='fail'
    )
}}

with source as (

    select external_subject_id from {{ source('legacy', 'data_portal_labmetadata') }}
    union
    select external_subject_id from {{ source('legacy', 'data_portal_limsrow') }}
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

differentiated as (

    select external_subject_id from cleaned
    {% if is_incremental() %}
    except
    select external_subject_id from {{ this }}
    {% endif %}

),

transformed as (

    select
        encode(sha256(cast(external_subject_id as bytea)), 'hex') as external_subject_hk,
        external_subject_id,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source,
        cast('{{ run_started_at }}' as timestamptz) as last_seen_datetime
    from
        differentiated

),

final as (

    select
        cast(external_subject_hk as char(64)) as external_subject_hk,
        cast(external_subject_id as varchar(255)) as external_subject_id,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(last_seen_datetime as timestamptz) as last_seen_datetime
    from
        transformed

)

select * from final
