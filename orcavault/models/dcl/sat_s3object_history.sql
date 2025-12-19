{{
    config(
        indexes=[
            {'columns': ['event_time'], 'type': 'btree'},
            {'columns': ['event_type'], 'type': 'btree'},
            {'columns': ['s3_object_id'], 'type': 'btree'},
            {'columns': ['ingest_id'], 'type': 'btree'},
            {'columns': ['storage_class'], 'type': 'btree'},
            {'columns': ['attributes'], 'type': 'gin'},
            {'columns': ['hash_diff'], 'type': 'btree'},
            {'columns': ['version_id'], 'type': 'btree'},
            {'columns': ['sequencer'], 'type': 'btree'},
        ],
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail'
    )
}}

with source as (

    select
        *
    from
        {{ source('ods', 'file_manager_s3_object') }}
    {% if is_incremental() %}
    where
        cast(event_time as timestamptz) > ( select coalesce(max(load_datetime), '1900-01-01') as ldts from {{ this }} )
    {% endif %}

),

transformed as (

    select
        encode(sha256(concat(bucket, "key")::bytea), 'hex') as s3object_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'file_manager_s3_object') as record_source,
        encode(sha256(concat(
            s3_object_id,
            event_type,
            version_id,
            event_time,
            "size",
            sha256,
            last_modified_date,
            e_tag,
            storage_class,
            sequencer,
            is_delete_marker,
            number_duplicate_events,
            attributes,
            deleted_date,
            deleted_sequencer,
            number_reordered,
            ingest_id,
            is_current_state,
            reason,
            archive_status,
            is_accessible
        )::bytea), 'hex') as hash_diff,
        *
    from
        source

),

final as (

    select
        cast(s3object_hk as char(64)) as s3object_hk,
        cast(hash_diff as char(64)) as s3object_sq,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(hash_diff as char(64)) as hash_diff,
        cast(s3_object_id as uuid) as s3_object_id,
        cast(event_type as varchar(255)) as event_type,
        cast(version_id as text) as version_id,
        cast(event_time as timestamptz) as event_time,
        cast("size" as bigint) as "size",
        cast(sha256 as text) as sha256,
        cast(last_modified_date as timestamptz) as last_modified_date,
        cast(e_tag as text) as e_tag,
        cast(storage_class as varchar(255)) as storage_class,
        cast(sequencer as text) as sequencer,
        cast(is_delete_marker as boolean) as is_delete_marker,
        cast(number_duplicate_events as bigint) as number_duplicate_events,
        cast(attributes as jsonb) as attributes,
        cast(deleted_date as timestamptz) as deleted_date,
        cast(deleted_sequencer as text) as deleted_sequencer,
        cast(number_reordered as bigint) as number_reordered,
        cast(ingest_id as uuid) as ingest_id,
        cast(is_current_state as boolean) as is_current_state,
        cast(reason as varchar(255)) as reason,
        cast(archive_status as varchar(255)) as archive_status,
        cast(is_accessible as boolean) as is_accessible
    from
        transformed

)

select * from final
