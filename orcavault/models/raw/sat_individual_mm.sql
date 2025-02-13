{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail'
    )
}}

with source as (

    select
        individual_id as internal_subject_id,
        orcabus_id,
        source
    from
        {{ source('ods', 'metadata_manager_individual') }}

),

cleaned as (

    select
        trim(regexp_replace(internal_subject_id, E'[\\n\\r]+', '', 'g')) as internal_subject_id,
        trim(regexp_replace(orcabus_id, E'[\\n\\r]+', '', 'g')) as orcabus_id,
        trim(regexp_replace(source, E'[\\n\\r]+', '', 'g')) as source
    from
        source

),

encoded as (

    select
        encode(sha256(cast(internal_subject_id as bytea)), 'hex') as internal_subject_hk,
        encode(sha256(concat(orcabus_id, source)::bytea), 'hex') as hash_diff,
        orcabus_id,
        source
    from
        cleaned

),

differentiated as (

    select
        internal_subject_hk,
        hash_diff
    from
        encoded
    {% if is_incremental() %}
    except
    select
        internal_subject_hk,
        hash_diff
    from
        {{ this }}
    {% endif %}

),

transformed as (

    select
        internal_subject_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'metadata_manager_individual') as record_source,
        hash_diff,
        orcabus_id,
        source
    from
        encoded
    {% if is_incremental() %}
    where
        internal_subject_hk in (select internal_subject_hk from differentiated)
    {% endif %}

),

final as (

    select
        cast(internal_subject_hk as char(64)) as internal_subject_hk,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(hash_diff as char(64)) as hash_diff,
        cast(orcabus_id as varchar(255)) as orcabus_id,
        cast(source as varchar(255)) as source
    from
        transformed

)

select * from final
