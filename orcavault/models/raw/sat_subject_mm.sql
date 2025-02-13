{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail'
    )
}}

with source as (

    select
        subject_id as external_subject_id,
        orcabus_id
    from
        {{ source('ods', 'metadata_manager_subject') }}

),

cleaned as (

    select
        trim(regexp_replace(external_subject_id, E'[\\n\\r]+', '', 'g')) as external_subject_id,
        trim(regexp_replace(orcabus_id, E'[\\n\\r]+', '', 'g')) as orcabus_id
    from
        source

),

encoded as (

    select
        encode(sha256(cast(external_subject_id as bytea)), 'hex') as external_subject_hk,
        encode(sha256(concat(orcabus_id)::bytea), 'hex') as hash_diff,
        orcabus_id
    from
        cleaned

),

differentiated as (

    select
        external_subject_hk,
        hash_diff
    from
        encoded
    {% if is_incremental() %}
    except
    select
        external_subject_hk,
        hash_diff
    from
        {{ this }}
    {% endif %}

),

transformed as (

    select
        external_subject_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'metadata_manager_subject') as record_source,
        hash_diff,
        orcabus_id
    from
        encoded
    {% if is_incremental() %}
    where
        external_subject_hk in (select external_subject_hk from differentiated)
    {% endif %}

),

final as (

    select
        cast(external_subject_hk as char(64)) as external_subject_hk,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(hash_diff as char(64)) as hash_diff,
        cast(orcabus_id as varchar(255)) as orcabus_id
    from
        transformed

)

select * from final
