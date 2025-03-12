{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail'
    )
}}

with source as (

    select
        *,
        row_number() over (partition by bucket, key, cast(event_time as date) order by cast(event_time as date) desc, is_current_state desc) as rank
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
        cast(event_time as timestamptz) as load_datetime,
        (select 'file_manager_s3_object') as record_source,
        encode(sha256(concat(
            s3_object_id,
            "size",
            e_tag,
            last_modified_date,
            sha256,
            event_type,
            event_time,
            version_id,
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
    where
        rank = 1

),

final as (

    select
        cast(s3object_hk as char(64)) as s3object_hk,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(hash_diff as char(64)) as hash_diff,
        cast(s3_object_id as uuid) as s3_object_id,
        cast("size" as bigint) as "size",
        cast(e_tag as varchar(255)) as e_tag,
        cast(last_modified_date as timestamptz) as last_modified_date,
        cast(sha256 as text) as sha256,
        cast(event_type as varchar(255)) as event_type,
        cast(event_time as timestamptz) as event_time,
        cast(version_id as varchar(255)) as version_id,
        cast(storage_class as varchar(255)) as storage_class,
        cast(sequencer as varchar(255)) as sequencer,
        cast(is_delete_marker as boolean) as is_delete_marker,
        cast(number_duplicate_events as bigint) as number_duplicate_events,
        cast(attributes as jsonb) as attributes,
        cast(deleted_date as timestamptz) as deleted_date,
        cast(deleted_sequencer as varchar(255)) as deleted_sequencer,
        cast(number_reordered as varchar(255)) as number_reordered,
        cast(ingest_id as uuid) as ingest_id,
        cast(is_current_state as boolean) as is_current_state,
        cast(reason as varchar(255)) as reason,
        cast(archive_status as varchar(255)) as archive_status,
        cast(is_accessible as boolean) as is_accessible
    from
        transformed

)

select * from final
