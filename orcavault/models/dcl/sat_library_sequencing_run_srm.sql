{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail'
    )
}}

with source as (

    select
        seq.instrument_run_id as sequencing_run_id,
        assoc.library_id as library_id,
        assoc.orcabus_id as orcabus_id,
        assoc.association_date as association_date,
        assoc.status as status
    from {{ source('ods', 'sequence_run_manager_sequence') }} seq
        join {{ source('ods', 'sequence_run_manager_libraryassociation') }} assoc on assoc.sequence_id = seq.orcabus_id
    {% if is_incremental() %}
    where
        cast(assoc.association_date as timestamptz) > ( select coalesce(max(load_datetime), '1900-01-01') as ldts from {{ this }} )
    {% endif %}

),

transformed as (

    select
        encode(sha256(cast(sequencing_run_id as bytea)), 'hex') as sequencing_run_hk,
        encode(sha256(cast(library_id as bytea)), 'hex') as library_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'sequence_run_manager_libraryassociation') as record_source,
        encode(sha256(concat(
            orcabus_id,
            association_date,
            status
        )::bytea), 'hex') as hash_diff,
        orcabus_id,
        association_date,
        status
    from
        source

),

final as (

    select
        cast(encode(sha256(concat(sequencing_run_hk, library_hk)::bytea), 'hex') as char(64)) as library_sequencing_run_hk,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(hash_diff as char(64)) as hash_diff,
        cast(orcabus_id as char(26)) as orcabus_id,
        cast(association_date as timestamptz) as association_date,
        cast(status as varchar(255)) as status
    from
        transformed

)

select * from final
