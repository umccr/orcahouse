with source as (

    select library_id, subject_id as internal_subject_id from {{ source('ods', 'data_portal_labmetadata') }}
    union
    select library_id, subject_id as internal_subject_id from {{ source('ods', 'data_portal_limsrow') }}
    union
    select lib.library_id as library_id, idv.individual_id as internal_subject_id from {{ source('ods', 'metadata_manager_library') }} as lib
        join {{ source('ods', 'metadata_manager_subject') }} as sbj on sbj.orcabus_id = lib.subject_orcabus_id
        join {{ source('ods', 'metadata_manager_subjectindividuallink') }} as lnk on lnk.subject_orcabus_id = sbj.orcabus_id
        join {{ source('ods', 'metadata_manager_individual') }} as idv on idv.orcabus_id = lnk.individual_orcabus_id
    union
    select library_id, subject_id as internal_subject_id from {{ ref('spreadsheet_library_tracking_metadata') }}
    union
    select library_id, subject_id as internal_subject_id from {{ ref('spreadsheet_google_lims') }}

),

cleaned as (

    select
        distinct library_id, internal_subject_id
    from
        source
    where
        (library_id is not null and library_id <> '') and
        (internal_subject_id is not null and internal_subject_id <> '')

),

transformed as (

    select
        encode(sha256(cast(internal_subject_id as bytea)), 'hex') as internal_subject_hk,
        encode(sha256(cast(library_id as bytea)), 'hex') as library_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source
    from
        cleaned

),

final as (

    select
        encode(sha256(concat(internal_subject_hk, library_hk)::bytea), 'hex') as library_internal_subject_hk,
        internal_subject_hk,
        library_hk,
        load_datetime,
        record_source
    from
        transformed

)

select * from final
