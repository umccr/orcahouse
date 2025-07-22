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
        cmt.orcabus_id as orcabus_id,
        cmt.created_by as created_by,
        cmt.created_at as created_at,
        cmt.updated_at as updated_at,
        cmt.is_deleted as is_deleted,
        cmt.comment as comment
    from {{ source('ods', 'sequence_run_manager_sequence') }} seq
        join {{ source('ods', 'sequence_run_manager_comment') }} cmt on cmt.target_id = seq.orcabus_id
    {% if is_incremental() %}
    where
        cast(cmt.created_at as timestamptz) > ( select coalesce(max(load_datetime), '1900-01-01') as ldts from {{ this }} )
    {% endif %}

),

transformed as (

    select
        encode(sha256(cast(sequencing_run_id as bytea)), 'hex') as sequencing_run_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'sequence_run_manager_comment') as record_source,
        encode(sha256(concat(
            orcabus_id,
            created_by,
            created_at,
            updated_at,
            is_deleted
        )::bytea), 'hex') as hash_diff,
        orcabus_id,
        created_by,
        created_at,
        updated_at,
        is_deleted,
        comment
    from
        source

),

final as (

    select
        cast(sequencing_run_hk as char(64)) as sequencing_run_hk,
        cast(hash_diff as char(64)) as sequencing_run_sq,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(hash_diff as char(64)) as hash_diff,
        cast(orcabus_id as char(26)) as orcabus_id,
        cast(created_by as varchar(255)) as created_by,
        cast(created_at as timestamptz) as created_at,
        cast(updated_at as timestamptz) as updated_at,
        cast(is_deleted as boolean) as is_deleted,
        cast(comment as text) as comment
    from
        transformed

)

select * from final
