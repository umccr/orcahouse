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
        {{ source('ods', 'metadata_manager_project') }}

),

cleaned as (

    select
        trim(regexp_replace(project_id, E'[\\n\\r]+', '', 'g')) as project_id,
        trim(regexp_replace(orcabus_id, E'[\\n\\r]+', '', 'g')) as orcabus_id,
        trim(regexp_replace(name, E'[\\n\\r]+', '', 'g')) as name,
        trim(regexp_replace(description, E'[\\n\\r]+', '', 'g')) as description
    from
        source

),

encoded as (

    select
        encode(sha256(cast(project_id as bytea)), 'hex') as project_hk,
        encode(sha256(concat(orcabus_id, name, description)::bytea), 'hex') as hash_diff,
        orcabus_id,
        name,
        description
    from
        cleaned

),

differentiated as (

    select
        project_hk,
        hash_diff
    from
        encoded
    {% if is_incremental() %}
    except
    select
        project_hk,
        hash_diff
    from
        {{ this }}
    {% endif %}

),

transformed as (

    select
        project_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'metadata_manager_project') as record_source,
        hash_diff,
        orcabus_id,
        name,
        description
    from
        encoded
    {% if is_incremental() %}
    where
        project_hk in (select project_hk from differentiated)
    {% endif %}

),

final as (

    select
        cast(project_hk as char(64)) as project_hk,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(hash_diff as char(64)) as hash_diff,
        cast(orcabus_id as varchar(255)) as orcabus_id,
        cast(name as varchar(255)) as name,
        cast(description as varchar(255)) as description
    from
        transformed

)

select * from final
