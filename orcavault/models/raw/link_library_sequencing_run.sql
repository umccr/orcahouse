with source as (

    select library_id, instrument_run_id as sequencing_run_id from {{ source('ods', 'data_portal_libraryrun') }}
    union
    select library_id, illumina_id as sequencing_run_id from {{ source('ods', 'data_portal_limsrow') }}

),

cleaned as (

    select
        distinct library_id, sequencing_run_id
    from
        source
    where
        (library_id is not null and library_id <> '') and
        (sequencing_run_id is not null and sequencing_run_id <> '')

),

transformed as (

    select
        encode(sha256(cast(sequencing_run_id as bytea)), 'hex') as sequencing_run_hk,
        encode(sha256(cast(library_id as bytea)), 'hex') as library_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source
    from
        cleaned

),

final as (

    select
        encode(sha256(concat(sequencing_run_hk, library_hk)::bytea), 'hex') as library_sequencing_run_hk,
        sequencing_run_hk,
        library_hk,
        load_datetime,
        record_source
    from
        transformed

)

select * from final
