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
            "size",
            e_tag,
            sha256,
            last_modified_date,
            event_time,
            event_type,
            version_id,
            is_delete_marker,
            sequencer,
            storage_class,
            attributes,
            ingest_id,
            reason,
            archive_status
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
        cast("size" as bigint) as "size",
        cast(e_tag as varchar(255)) as e_tag,
        cast(sha256 as text) as sha256,
        cast(last_modified_date as timestamptz) as last_modified_date,
        cast(event_time as timestamptz) as event_time,
        cast(event_type as varchar(255)) as event_type,
        cast(version_id as varchar(255)) as version_id,
        cast(is_delete_marker as boolean) as is_delete_marker,
        cast(sequencer as varchar(255)) as sequencer,
        cast(storage_class as varchar(255)) as storage_class,
        cast(attributes as jsonb) as attributes,
        cast(ingest_id as uuid) as ingest_id,
        cast(reason as varchar(255)) as reason,
        cast(archive_status as varchar(255)) as archive_status
    from
        transformed

)

select * from final
