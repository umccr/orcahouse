with source as (

    select library_id, external_subject_id from {{ source('ods', 'data_portal_labmetadata') }}
    union
    select library_id, external_subject_id from {{ source('ods', 'data_portal_limsrow') }}
    union
    select lib.library_id as library_id, sbj.subject_id as external_subject_id from {{ source('ods', 'metadata_manager_library') }} as lib
        join {{ source('ods', 'metadata_manager_subject') }} as sbj on sbj.orcabus_id = lib.subject_orcabus_id

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

transformed as (

    select
        encode(sha256(cast(external_subject_id as bytea)), 'hex') as external_subject_hk,
        encode(sha256(cast(library_id as bytea)), 'hex') as library_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source
    from
        cleaned

),

final as (

    select
        encode(sha256(concat(external_subject_hk, library_hk)::bytea), 'hex') as library_external_subject_hk,
        external_subject_hk,
        library_hk,
        load_datetime,
        record_source
    from
        transformed

)

select * from final
