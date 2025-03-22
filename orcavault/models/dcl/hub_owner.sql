{{
    config(
        indexes=[
            {'columns': ['owner_id'], 'type': 'btree'},
            {'columns': ['load_datetime'], 'type': 'btree'},
            {'columns': ['last_seen_datetime'], 'type': 'btree'},
            {'columns': ['owner_id', 'last_seen_datetime'], 'type': 'btree'},
        ],
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='owner_hk',
        merge_update_columns=['last_seen_datetime'],
        on_schema_change='fail'
    )
}}

with source as (

    select project_owner as owner_id from {{ source('ods', 'data_portal_labmetadata') }}
    union
    select project_owner as owner_id from {{ source('ods', 'data_portal_limsrow') }}
    union
    select contact_id as owner_id from {{ source('ods', 'metadata_manager_contact') }}
    union
    select project_owner as owner_id from {{ ref('spreadsheet_library_tracking_metadata') }}
    union
    select project_owner as owner_id from {{ ref('spreadsheet_google_lims') }}

),

cleaned as (

    select * from source where owner_id is not null and owner_id <> ''

),

differentiated as (

    select owner_id from cleaned
    {% if is_incremental() %}
    except
    select owner_id from {{ this }}
    {% endif %}

),

transformed as (

    select
        encode(sha256(cast(owner_id as bytea)), 'hex') as owner_hk,
        owner_id,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source,
        cast('{{ run_started_at }}' as timestamptz) as last_seen_datetime
    from
        differentiated

),

final as (

    select
        cast(owner_hk as char(64)) as owner_hk,
        cast(owner_id as varchar(255)) as owner_id,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(last_seen_datetime as timestamptz) as last_seen_datetime
    from
        transformed

)

select * from final
