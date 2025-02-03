{{
    config(
        indexes=[
            {'columns': ['contact_id'], 'type': 'btree'},
        ],
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='contact_id',
        on_schema_change='fail'
    )
}}

with source as (

    select project_owner as contact_id from {{ source('ods', 'data_portal_labmetadata') }}
    union
    select project_owner as contact_id from {{ source('ods', 'data_portal_limsrow') }}
    union
    select contact_id from {{ source('ods', 'metadata_manager_contact') }}
    union
    select project_owner as contact_id from {{ ref('spreadsheet_library_tracking_metadata') }}
    union
    select project_owner as contact_id from {{ ref('spreadsheet_google_lims') }}

),

cleaned as (

    select * from source where contact_id is not null and contact_id <> ''

),

differentiated as (

    select contact_id from cleaned
    except
    select contact_id from {{ this }}

),

transformed as (

    select
        encode(sha256(cast(contact_id as bytea)), 'hex') as contact_hk,
        contact_id,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source
    from
        differentiated

),

final as (

    select
        cast(contact_hk as char(64)) as contact_hk,
        cast(contact_id as varchar(255)) as contact_id,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source
    from
        transformed

)

select * from final
