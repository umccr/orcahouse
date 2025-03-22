{{
    config(
        indexes=[
            {'columns': ['bucket'], 'type': 'btree'},
            {'columns': ['key'], 'type': 'btree'},
            {'columns': ['load_datetime'], 'type': 'btree'},
            {'columns': ['last_seen_datetime'], 'type': 'btree'},
            {'columns': ['bucket', 'key'], 'type': 'btree'},
            {'columns': ['key', 'last_seen_datetime'], 'type': 'btree'},
            {'columns': ['bucket', 'key', 'last_seen_datetime'], 'type': 'btree'},
        ],
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='s3object_hk',
        merge_update_columns=['last_seen_datetime'],
        on_schema_change='fail'
    )
}}

with source1 as (

    select
        bucket,
        "key"
    from
        {{ source('ods', 'data_portal_s3object') }}
    {% if is_incremental() %}
    where
        cast(last_modified_date as timestamptz) > ( select coalesce(max(load_datetime), '1900-01-01') as ldts from {{ this }} )
    {% endif %}

),

source2 as (

    select
        bucket,
        "key"
    from
        {{ source('ods', 'file_manager_s3_object') }}
    {% if is_incremental() %}
    where
        cast(event_time as timestamptz) > ( select coalesce(max(load_datetime), '1900-01-01') as ldts from {{ this }} )
    {% endif %}

),

combined as (

    select bucket, "key" from source1
    union
    select bucket, "key" from source2

),

transformed as (

    select
        encode(sha256(concat(bucket, "key")::bytea), 'hex') as s3object_hk,
        bucket,
        "key",
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 's3') as record_source,
        cast('{{ run_started_at }}' as timestamptz) as last_seen_datetime
    from
        combined

),

final as (

    select
        cast(s3object_hk as char(64)) as s3object_hk,
        cast(bucket as varchar(255)) as bucket,
        cast("key" as text) as "key",
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(last_seen_datetime as timestamptz) as last_seen_datetime
    from
        transformed

)

select * from final
