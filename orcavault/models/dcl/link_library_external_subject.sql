{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key=['external_subject_hk', 'library_hk'],
        on_schema_change='fail'
    )
}}

with source as (

    select library_id, external_subject_id from {{ source('legacy', 'data_portal_labmetadata') }}
    union
    select library_id, external_subject_id from {{ source('legacy', 'data_portal_limsrow') }}
    union
    select lib.library_id as library_id, sbj.subject_id as external_subject_id from {{ source('ods', 'metadata_manager_library') }} as lib
        join {{ source('ods', 'metadata_manager_subject') }} as sbj on sbj.orcabus_id = lib.subject_orcabus_id
    union
    select library_id, external_subject_id from {{ ref('spreadsheet_library_tracking_metadata') }}
    union
    select library_id, external_subject_id from {{ ref('spreadsheet_google_lims') }}

),

cleaned as (

    select
        distinct library_id, trim(external_subject_id) as external_subject_id
    from
        source
    where
        (library_id is not null and library_id <> '') and
        (external_subject_id is not null and external_subject_id <> '')

),

differentiated as (

    select
        encode(sha256(cast(external_subject_id as bytea)), 'hex') as external_subject_hk,
        encode(sha256(cast(library_id as bytea)), 'hex') as library_hk
    from
        cleaned
    {% if is_incremental() %}
    except
    select
        external_subject_hk,
        library_hk
    from
        {{ this }}
    {% endif %}

),

transformed as (

    select
        external_subject_hk,
        library_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source
    from
        differentiated

),

final as (

    select
        cast(encode(sha256(concat(external_subject_hk, library_hk)::bytea), 'hex') as char(64)) as library_external_subject_hk,
        cast(external_subject_hk as char(64)) as external_subject_hk,
        cast(library_hk as char(64)) as library_hk,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source
    from
        transformed

)

select * from final
