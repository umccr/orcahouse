{{
    config(
        indexes=[
            {'columns': ['base_library_id'], 'type': 'btree'},
            {'columns': ['alias_library_id'], 'type': 'btree'},
        ],
        materialized='incremental',
        incremental_strategy='merge',
        unique_key='sal_library_hk',
        on_schema_change='fail'
    )
}}

with source as (

    select
        *
    from
        {{ ref('hub_library') }}
    {% if is_incremental() %}
    where
        cast(load_datetime as timestamptz) > ( select coalesce(max(load_datetime), '1900-01-01') as ldts from {{ this }} )
    {% endif %}

),

filtered as (

    select
        library_hk as alias_library_hk,
        library_id as alias_library_id,
        {{ extract_library_id("library_id") }} as base_library_id,
        record_source
    from
        source
    where
        library_id like '%topup%' or library_id like '%rerun%'

),

transformed as (

    select
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        record_source,
        encode(sha256(cast(base_library_id as bytea)), 'hex') as base_library_hk,
        alias_library_hk,
        base_library_id,
        alias_library_id
    from
        filtered

),

final as (

    select
        cast(encode(sha256(concat(base_library_hk, alias_library_hk)::bytea), 'hex') as char(64)) as sal_library_hk,
        cast(base_library_hk as char(64)) as base_library_hk,
        cast(alias_library_hk as char(64)) as alias_library_hk,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(base_library_id as varchar(255)) as base_library_id,
        cast(alias_library_id as varchar(255)) as alias_library_id
    from
        transformed

)

select * from final
