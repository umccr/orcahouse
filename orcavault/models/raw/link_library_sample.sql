with source as (

    select library_id, sample_id from {{ source('ods', 'data_portal_limsrow') }}
    union
    select library_id, sample_id from {{ source('ods', 'data_portal_labmetadata') }}
    union
    select library_id, smp.sample_id as sample_id from {{ source('ods', 'metadata_manager_library') }} as lib
        join {{ source('ods', 'metadata_manager_sample') }} as smp on lib.sample_orcabus_id = smp.orcabus_id

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

transformed as (

    select
        encode(sha256(cast(sample_id as bytea)), 'hex') as sample_hk,
        encode(sha256(cast(library_id as bytea)), 'hex') as library_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source
    from
        cleaned

),

final as (

    select
        encode(sha256(concat(sample_hk, library_hk)::bytea), 'hex') as library_sample_hk,
        sample_hk,
        library_hk,
        load_datetime,
        record_source
    from
        transformed

)

select * from final
