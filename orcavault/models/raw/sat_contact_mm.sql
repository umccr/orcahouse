{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail'
    )
}}

with source as (

    select
        *
    from
        {{ source('ods', 'metadata_manager_contact') }}

),

cleaned as (

    select
        trim(regexp_replace(contact_id, E'[\\n\\r]+', '', 'g')) as contact_id,
        trim(regexp_replace(orcabus_id, E'[\\n\\r]+', '', 'g')) as orcabus_id,
        trim(regexp_replace(name, E'[\\n\\r]+', '', 'g')) as name,
        trim(regexp_replace(description, E'[\\n\\r]+', '', 'g')) as description,
        trim(regexp_replace(email, E'[\\n\\r]+', '', 'g')) as email
    from
        source

),

encoded as (

    select
        encode(sha256(cast(contact_id as bytea)), 'hex') as contact_hk,
        encode(sha256(concat(orcabus_id, name, description, email)::bytea), 'hex') as hash_diff,
        orcabus_id,
        name,
        description,
        email
    from
        cleaned

),

differentiated as (

    select
        contact_hk,
        hash_diff
    from
        encoded
    {% if is_incremental() %}
    except
    select
        contact_hk,
        hash_diff
    from
        {{ this }}
    {% endif %}

),

transformed as (

    select
        contact_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'metadata_manager_contact') as record_source,
        hash_diff,
        orcabus_id,
        name,
        description,
        email
    from
        encoded
    {% if is_incremental() %}
    where
        contact_hk in (select contact_hk from differentiated)
    {% endif %}

),

final as (

    select
        cast(contact_hk as char(64)) as contact_hk,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(hash_diff as char(64)) as hash_diff,
        cast(orcabus_id as varchar(255)) as orcabus_id,
        cast(name as varchar(255)) as name,
        cast(description as varchar(255)) as description,
        cast(email as varchar(255)) as email
    from
        transformed

)

select * from final
