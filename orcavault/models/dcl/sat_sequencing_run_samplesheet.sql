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
        ss.orcabus_id as orcabus_id,
        ss.association_status as association_status,
        ss.association_timestamp as association_timestamp,
        ss.sample_sheet_name as samplesheet_name,
        ss.sample_sheet_content as samplesheet_content
    from {{ source('ods', 'sequence_run_manager_sequence') }} seq
        join {{ source('ods', 'sequence_run_manager_samplesheet') }} ss on ss.sequence_id = seq.orcabus_id
    {% if is_incremental() %}
    where
        cast(ss.association_timestamp as timestamptz) > ( select coalesce(max(load_datetime), '1900-01-01') as ldts from {{ this }} )
    {% endif %}

),

transformed as (

    select
        encode(sha256(cast(sequencing_run_id as bytea)), 'hex') as sequencing_run_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'sequence_run_manager_samplesheet') as record_source,
        encode(sha256(concat(
            orcabus_id,
            association_status,
            association_timestamp,
            samplesheet_name
        )::bytea), 'hex') as hash_diff,
        orcabus_id,
        association_status,
        association_timestamp,
        samplesheet_name,
        samplesheet_content
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
        cast(association_status as varchar(255)) as association_status,
        cast(association_timestamp as timestamptz) as association_timestamp,
        cast(samplesheet_name as varchar(255)) as samplesheet_name,
        cast(samplesheet_content as jsonb) as samplesheet_content
    from
        transformed

)

select * from final
