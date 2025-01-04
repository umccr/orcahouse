with source as (

    select sample_id, external_sample_id from {{ source('ods', 'data_portal_labmetadata') }}
    union
    select sample_id, external_sample_id from {{ source('ods', 'data_portal_limsrow') }}
    union
    select sample_id, external_sample_id from {{ source('ods', 'metadata_manager_sample') }}

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

transformed as (

    select
        encode(sha256(cast(external_sample_id as bytea)), 'hex') as external_sample_hk,
        encode(sha256(cast(sample_id as bytea)), 'hex') as sample_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source
    from
        cleaned

),

final as (

    select
        encode(sha256(concat(external_sample_hk, sample_hk)::bytea), 'hex') as internal_external_sample_hk,
        external_sample_hk,
        sample_hk,
        load_datetime,
        record_source
    from
        transformed

)

select * from final
