{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key=['external_sample_hk', 'sample_hk'],
        on_schema_change='fail'
    )
}}

with source as (

    select sample_id, external_sample_id from {{ source('ods', 'data_portal_labmetadata') }}
    union
    select sample_id, external_sample_id from {{ source('ods', 'data_portal_limsrow') }}
    union
    select sample_id, external_sample_id from {{ source('ods', 'metadata_manager_sample') }}
    union
    select sample_id, external_sample_id from {{ ref('spreadsheet_library_tracking_metadata') }}
    union
    select sample_id, external_sample_id from {{ ref('spreadsheet_google_lims') }}

),

cleaned as (

    select
        distinct sample_id, trim(external_sample_id) as external_sample_id
    from
        source
    where
        (sample_id is not null and sample_id <> '') and
        (external_sample_id is not null and external_sample_id <> '')

),

differentiated as (

    select
        encode(sha256(cast(external_sample_id as bytea)), 'hex') as external_sample_hk,
        encode(sha256(cast(sample_id as bytea)), 'hex') as sample_hk
    from
        cleaned
    {% if is_incremental() %}
    except
    select
        external_sample_hk,
        sample_hk
    from
        {{ this }}
    {% endif %}

),

transformed as (

    select
        external_sample_hk,
        sample_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source
    from
        differentiated

),

final as (

    select
        cast(encode(sha256(concat(external_sample_hk, sample_hk)::bytea), 'hex') as char(64)) as internal_external_sample_hk,
        cast(external_sample_hk as char(64)) as external_sample_hk,
        cast(sample_hk as char(64)) as sample_hk,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source
    from
        transformed

)

select * from final
