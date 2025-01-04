with source as (

    select subject_id as internal_subject_id, external_subject_id from {{ source('ods', 'data_portal_labmetadata') }}
    union
    select subject_id as internal_subject_id, external_subject_id from {{ source('ods', 'data_portal_limsrow') }}
    union
    select idv.individual_id as internal_subject_id, sbj.subject_id as external_subject_id from {{ source('ods', 'metadata_manager_subject') }} as sbj
        join {{ source('ods', 'metadata_manager_subjectindividuallink') }} as lnk on lnk.subject_orcabus_id = sbj.orcabus_id
        join {{ source('ods', 'metadata_manager_individual') }} as idv on lnk.individual_orcabus_id = idv.orcabus_id

),

cleaned as (

    select
        distinct internal_subject_id, trim(external_subject_id) as external_subject_id
    from
        source
    where
        (internal_subject_id is not null and internal_subject_id <> '') and
        (external_subject_id is not null and external_subject_id <> '')

),

transformed as (

    select
        encode(sha256(cast(external_subject_id as bytea)), 'hex') as external_subject_hk,
        encode(sha256(cast(internal_subject_id as bytea)), 'hex') as internal_subject_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source
    from
        cleaned

),

final as (

    select
        encode(sha256(concat(external_subject_hk, internal_subject_hk)::bytea), 'hex') as internal_external_subject_hk,
        external_subject_hk,
        internal_subject_hk,
        load_datetime,
        record_source
    from
        transformed

)

select * from final
