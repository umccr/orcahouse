{{
    config(
        indexes=[
            {'columns': ['internal_subject_id'], 'type': 'btree'},
            {'columns': ['load_datetime'], 'type': 'btree'},
            {'columns': ['last_seen_datetime'], 'type': 'btree'},
            {'columns': ['internal_subject_id', 'last_seen_datetime'], 'type': 'btree'},
        ],
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='internal_subject_hk',
        merge_update_columns=['last_seen_datetime'],
        on_schema_change='fail'
    )
}}

with source as (

    select subject_id as internal_subject_id from {{ source('legacy', 'data_portal_labmetadata') }}
    union
    select subject_id as internal_subject_id from {{ source('legacy', 'data_portal_limsrow') }}
    union
    select individual_id as internal_subject_id from {{ source('ods', 'metadata_manager_individual') }}
    union
    select subject_id as internal_subject_id from {{ ref('spreadsheet_library_tracking_metadata') }}
    union
    select subject_id as internal_subject_id from {{ ref('spreadsheet_google_lims') }}

),

cleaned as (

    select * from source where internal_subject_id is not null and internal_subject_id <> ''

),

differentiated as (

    select internal_subject_id from cleaned
    {% if is_incremental() %}
    except
    select internal_subject_id from {{ this }}
    {% endif %}

),

transformed as (

    select
        encode(sha256(cast(internal_subject_id as bytea)), 'hex') as internal_subject_hk,
        internal_subject_id,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source,
        cast('{{ run_started_at }}' as timestamptz) as last_seen_datetime
    from
        differentiated

),

final as (

    select
        cast(internal_subject_hk as char(64)) as internal_subject_hk,
        cast(internal_subject_id as varchar(255)) as internal_subject_id,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(last_seen_datetime as timestamptz) as last_seen_datetime
    from
        transformed

)

select * from final
