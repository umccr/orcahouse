{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key=['sequencing_run_hk', 'library_hk'],
        on_schema_change='fail'
    )
}}

with source as (

    select library_id, instrument_run_id as sequencing_run_id from {{ source('legacy', 'data_portal_libraryrun') }}
    union
    select library_id, illumina_id as sequencing_run_id from {{ source('legacy', 'data_portal_limsrow') }}
    union
    select library_id, illumina_id as sequencing_run_id from {{ ref('spreadsheet_google_lims') }}
    union
    select
        assoc.library_id as library_id, seq.instrument_run_id as sequencing_run_id
    from {{ source('ods', 'sequence_run_manager_sequence') }} seq
        join {{ source('ods', 'sequence_run_manager_libraryassociation') }} assoc on assoc.sequence_id = seq.orcabus_id

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

differentiated as (

    select
        encode(sha256(cast(sequencing_run_id as bytea)), 'hex') as sequencing_run_hk,
        encode(sha256(cast(library_id as bytea)), 'hex') as library_hk
    from
        cleaned
    {% if is_incremental() %}
    except
    select
        sequencing_run_hk,
        library_hk
    from
        {{ this }}
    {% endif %}

),

transformed as (

    select
        sequencing_run_hk,
        library_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'lab') as record_source
    from
        differentiated

),

final as (

    select
        cast(encode(sha256(concat(sequencing_run_hk, library_hk)::bytea), 'hex') as char(64)) as library_sequencing_run_hk,
        cast(sequencing_run_hk as char(64)) as sequencing_run_hk,
        cast(library_hk as char(64)) as library_hk,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source
    from
        transformed

)

select * from final
