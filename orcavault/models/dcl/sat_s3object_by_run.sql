{{
    config(
        indexes=[
            {'columns': ['portal_run_id'], 'type': 'btree'},
            {'columns': ['sequencing_run_id'], 'type': 'btree'},
            {'columns': ['sequencing_run_id', 'portal_run_id'], 'type': 'btree'},
            {'columns': ['sequencing_run_id', 'portal_run_id', 'ext1', 'ext2'], 'type': 'btree'},
            {'columns': ['ext1'], 'type': 'btree'},
            {'columns': ['ext2'], 'type': 'btree'},
            {'columns': ['ext1', 'ext2'], 'type': 'btree'},
            {'columns': ['filename'], 'type': 'btree'},
            {'columns': ['hash_diff'], 'type': 'btree'},
        ],
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='hash_diff',
        merge_update_columns=['filename', 'ext1', 'ext2', 'ext3'],
        on_schema_change='fail'
    )
}}

with source as (

    select
        s3object_hk,
        {{ extract_portal_run_id("key") }} as portal_run_id,
        {{ extract_sequencing_run_id("key") }} as sequencing_run_id,
        regexp_replace("key", '^.+[/\\]', '') as filename,
        split_part(regexp_replace("key", '^.+[/\\]', ''), '.', -1) as ext1,
        split_part(regexp_replace("key", '^.+[/\\]', ''), '.', -2) as ext2,
        split_part(regexp_replace("key", '^.+[/\\]', ''), '.', -3) as ext3,
        load_datetime,
        record_source
    from
        {{ ref('hub_s3object') }}
    {% if is_incremental() %}
    where
        cast(load_datetime as timestamptz) > ( select coalesce(max(load_datetime), '1900-01-01') as ldts from {{ this }} )
    {% endif %}
    group by s3object_hk, portal_run_id, sequencing_run_id

),

transformed as (

    select
        s3object_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        record_source,
        encode(sha256(concat(s3object_hk, portal_run_id, sequencing_run_id)::bytea), 'hex') as hash_diff,
        portal_run_id,
        sequencing_run_id,
        filename,
        ext1,
        ext2,
        ext3
    from
        source

),

final as (

    select
        cast(s3object_hk as char(64)) as s3object_hk,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(hash_diff as char(64)) as hash_diff,
        cast(portal_run_id as char(16)) as portal_run_id,
        cast(sequencing_run_id as varchar(255)) as sequencing_run_id,
        cast(filename as text) as filename,
        cast(ext1 as varchar(255)) as ext1,
        cast(ext2 as varchar(255)) as ext2,
        cast(ext3 as varchar(255)) as ext3
    from
        transformed

)

select * from final
