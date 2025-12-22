{{
    config(
        indexes=[
            {'columns': ['effective_from'], 'type': 'btree'},
            {'columns': ['effective_to'], 'type': 'btree'},
            {'columns': ['is_current'], 'type': 'btree'},
            {'columns': ['is_deleted'], 'type': 'btree'},
            {'columns': ['is_current', 'is_deleted'], 'type': 'btree'},
            {'columns': ['is_current', 'is_deleted', 'version_active'], 'type': 'btree'},
            {'columns': ['effective_from', 'effective_to'], 'type': 'btree'},
            {'columns': ['s3_object_id'], 'type': 'btree'},
            {'columns': ['ingest_id'], 'type': 'btree'},
            {'columns': ['storage_class'], 'type': 'btree'},
            {'columns': ['attributes'], 'type': 'gin'},
            {'columns': ['reason'], 'type': 'btree'},
            {'columns': ['hash_diff'], 'type': 'btree'},
            {'columns': ['version_id'], 'type': 'btree'},
            {'columns': ['version_active'], 'type': 'btree'},
        ],
        materialized='incremental',
        incremental_strategy='merge',
        unique_key=['s3object_hk', 'hash_diff'],
        merge_update_columns = ['effective_to', 'is_current', 'is_deleted'],
        on_schema_change='fail'
    )
}}

with incremental as (

    select
        distinct s3object_hk, version_id
    from
        {{ ref('sat_s3object_history') }}
    {% if is_incremental() %}
    where
        cast(event_time as timestamptz) > ( select coalesce(max(load_datetime), '1900-01-01') as ldts from {{ this }} )
    {% endif %}

),

history as (

    select
        h.*,
        row_number() over (partition by h.s3object_hk, h.version_id order by h.event_time desc, h.sequencer desc) as rank_by_group
    from
        {{ ref('sat_s3object_history') }} h
        join incremental i on i.s3object_hk = h.s3object_hk and i.version_id = h.version_id

),

transformed as (

    select
        s3object_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        record_source,
        encode(sha256(concat(
            s3_object_id,
            "size",
            e_tag,
            sha256,
            last_modified_date,
            storage_class,
            attributes,
            ingest_id,
            reason,
            version_id,
            is_current_state
        )::bytea), 'hex') as hash_diff,
        s3_object_id,
        "size",
        e_tag,
        sha256,
        last_modified_date,
        storage_class,
        attributes,
        ingest_id,
        reason,
        version_id,
        is_current_state as version_active,
        cast(event_time as timestamptz) as effective_from,
        case
            when (rank_by_group = 1) then
                cast('9999-12-31' as date)
            else
                lag(event_time) over (partition by s3object_hk, version_id order by rank_by_group)
            end as effective_to,
        case when (rank_by_group = 1) then 1 else 0 end as is_current,
        case when (event_type = 'Deleted') then 1 else 0 end as is_deleted
    from
        history

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
        cast(e_tag as text) as e_tag,
        cast(sha256 as text) as sha256,
        cast(last_modified_date as timestamptz) as last_modified_date,
        cast(storage_class as varchar(255)) as storage_class,
        cast(attributes as jsonb) as attributes,
        cast(ingest_id as uuid) as ingest_id,
        cast(reason as varchar(255)) as reason,
        cast(version_id as text) as version_id,
        cast(version_active as boolean) as version_active,
        cast(effective_from as timestamptz) as effective_from,
        cast(effective_to as timestamptz) as effective_to,
        cast(is_current as smallint) as is_current,
        cast(is_deleted as smallint) as is_deleted
    from
        transformed

)

select * from final
