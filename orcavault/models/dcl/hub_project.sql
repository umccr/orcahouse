{{
    config(
        indexes=[
            {'columns': ['project_id'], 'type': 'btree'},
            {'columns': ['load_datetime'], 'type': 'btree'},
            {'columns': ['last_seen_datetime'], 'type': 'btree'},
            {'columns': ['project_id', 'last_seen_datetime'], 'type': 'btree'},
        ],
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='project_hk',
        merge_update_columns=['last_seen_datetime'],
        on_schema_change='fail'
    )
}}

with source as (

    select project_name as project_id from {{ source('legacy', 'data_portal_labmetadata') }}
    union
    select project_name as project_id from {{ source('legacy', 'data_portal_limsrow') }}
    union
    select project_id from {{ source('ods', 'metadata_manager_project') }}
    union
    select project_name as project_id from {{ ref('spreadsheet_library_tracking_metadata') }}
    union
    select project_name as project_id from {{ ref('spreadsheet_google_lims') }}

),

cleaned as (

    select * from source where project_id is not null and project_id <> ''

),

differentiated as (

    select project_id from cleaned
    {% if is_incremental() %}
    except
    select project_id from {{ this }}
    {% endif %}

),

transformed as (

    select
        encode(sha256(cast(project_id as bytea)), 'hex') as project_hk,
        project_id,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source,
        cast('{{ run_started_at }}' as timestamptz) as last_seen_datetime
    from
        differentiated

),

final as (

    select
        cast(project_hk as char(64)) as project_hk,
        cast(project_id as varchar(255)) as project_id,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(last_seen_datetime as timestamptz) as last_seen_datetime
    from
        transformed

)

select * from final
