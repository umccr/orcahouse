{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        on_schema_change='fail'
    )
}}

with source as (

    select
        bucket,
        "key",
        cast(last_modified_date as timestamptz) as last_seen_date
    from
        {{ source('ods', 'data_portal_s3object') }}
    union
    select
        bucket,
        "key",
        cast(event_time as timestamptz) as last_seen_date
    from
        {{ source('ods', 'file_manager_s3_object') }}

),

cleaned as (

    select
        bucket,
        "key",
        last_seen_date,
        row_number() over (partition by bucket, "key" order by last_seen_date desc) as rank
    from
        source

),

differentiated as (

    select
        *
    from
        cleaned
    where
        rank = 1
    {% if is_incremental() %}
        and cast(last_seen_date as timestamptz) > ( select coalesce(max(load_datetime), '1900-01-01') as ldts from {{ this }} )
    {% endif %}

),

transformed as (

    select
        encode(sha256(concat(bucket, "key")::bytea), 'hex') as s3object_hk,
        bucket,
        "key",
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 's3') as record_source
    from
        differentiated

),

final as (

    select
        cast(s3object_hk as char(64)) as s3object_hk,
        cast(bucket as varchar(255)) as bucket,
        cast("key" as text) as "key",
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source
    from
        transformed

)

select * from final
