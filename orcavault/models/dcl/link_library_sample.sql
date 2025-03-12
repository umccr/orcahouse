{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key=['sample_hk', 'library_hk'],
        on_schema_change='fail'
    )
}}

with source as (

    select library_id, sample_id from {{ source('ods', 'data_portal_limsrow') }}
    union
    select library_id, sample_id from {{ source('ods', 'data_portal_labmetadata') }}
    union
    select library_id, smp.sample_id as sample_id from {{ source('ods', 'metadata_manager_library') }} as lib
        join {{ source('ods', 'metadata_manager_sample') }} as smp on lib.sample_orcabus_id = smp.orcabus_id
    union
    select library_id, sample_id from {{ ref('spreadsheet_library_tracking_metadata') }}
    union
    select library_id, sample_id from {{ ref('spreadsheet_google_lims') }}

),

cleaned as (

    select
        distinct library_id, sample_id
    from
        source
    where
        (library_id is not null and library_id <> '') and
        (sample_id is not null and sample_id <> '')

),

differentiated as (

    select
        encode(sha256(cast(sample_id as bytea)), 'hex') as sample_hk,
        encode(sha256(cast(library_id as bytea)), 'hex') as library_hk
    from
        cleaned
    {% if is_incremental() %}
    except
    select
        sample_hk,
        library_hk
    from
        {{ this }}
    {% endif %}

),

transformed as (

    select
        sample_hk,
        library_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source
    from
        differentiated

),

final as (

    select
        cast(encode(sha256(concat(sample_hk, library_hk)::bytea), 'hex') as char(64)) as library_sample_hk,
        cast(sample_hk as char(64)) as sample_hk,
        cast(library_hk as char(64)) as library_hk,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source
    from
        transformed

)

select * from final
