{{
    config(
        indexes=[
            {'columns': ['is_deleted'], 'type': 'btree'},
            {'columns': ['id'], 'type': 'btree'},
            {'columns': ['last_modified_date'], 'type': 'btree'},
            {'columns': ['hash_diff'], 'type': 'btree'},
        ],
        materialized='incremental',
        incremental_strategy='merge',
        unique_key=['s3object_hk', 'load_datetime'],
        merge_update_columns = ['is_deleted'],
        on_schema_change='fail'
    )
}}

with source as (

    select
        id,
        bucket,
        "key",
        "size",
        e_tag,
        cast(last_modified_date as timestamptz) as last_modified_date
    from
        {{ source('legacy', 'data_portal_s3object') }}
    {% if is_incremental() %}
    where
        cast(last_modified_date as timestamptz) > ( select coalesce(max(load_datetime), '1900-01-01') as ldts from {{ this }} )
    {% endif %}

),

transformed as (

    select
        encode(sha256(concat(bucket, "key")::bytea), 'hex') as s3object_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'data_portal_s3object') as record_source,
        encode(sha256(concat(id, "size", e_tag, last_modified_date)::bytea), 'hex') as hash_diff,
        id,
        "size",
        e_tag,
        last_modified_date,
        (select 0) as is_deleted
    from
        source

),

final as (

    select
        cast(s3object_hk as char(64)) as s3object_hk,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(hash_diff as char(64)) as hash_diff,
        cast(id as bigint) as id,
        cast("size" as bigint) as "size",
        cast(e_tag as varchar(255)) as e_tag,
        cast(last_modified_date as timestamptz) as last_modified_date,
        cast(is_deleted as smallint) as is_deleted
    from
        transformed

)

select * from final
{% if is_incremental() %}
union
    select
        cast(t.s3object_hk as char(64)) as s3object_hk,
        cast(t.load_datetime as timestamptz) as load_datetime,
        cast(t.record_source as varchar(255)) as record_source,
        cast(t.hash_diff as char(64)) as hash_diff,
        cast(t.id as bigint) as id,
        cast(t."size" as bigint) as "size",
        cast(t.e_tag as varchar(255)) as e_tag,
        cast(t.last_modified_date as timestamptz) as last_modified_date,
        cast((select 1) as smallint) as is_deleted
    from {{ this }} t
        left join {{ source('legacy', 'data_portal_s3object') }} s on s.id = t.id
    where
        s.id is null and t.is_deleted = 0
{% endif %}
