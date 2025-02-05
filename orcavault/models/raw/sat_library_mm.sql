{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail'
    )
}}

with source as (

    select
        library_id,
        orcabus_id,
        workflow,
        phenotype,
        type,
        assay,
        quality
    from
        {{ source('ods', 'metadata_manager_library') }}

),

cleaned as (

    select
        trim(regexp_replace(library_id, E'[\\n\\r]+', '', 'g')) as library_id,
        trim(regexp_replace(orcabus_id, E'[\\n\\r]+', '', 'g')) as orcabus_id,
        trim(regexp_replace(workflow, E'[\\n\\r]+', '', 'g')) as workflow,
        trim(regexp_replace(phenotype, E'[\\n\\r]+', '', 'g')) as phenotype,
        trim(regexp_replace(type, E'[\\n\\r]+', '', 'g')) as type,
        trim(regexp_replace(assay, E'[\\n\\r]+', '', 'g')) as assay,
        trim(regexp_replace(quality, E'[\\n\\r]+', '', 'g')) as quality
    from
        source

),

encoded as (

    select
        encode(sha256(cast(library_id as bytea)), 'hex') as library_hk,
        encode(sha256(concat(orcabus_id, workflow, phenotype, type, assay, quality)::bytea), 'hex') as hash_diff,
        orcabus_id,
        workflow,
        phenotype,
        type,
        assay,
        quality
    from
        cleaned

),

differentiated as (

    select
        library_hk,
        hash_diff
    from
        encoded
    {% if is_incremental() %}
    except
    select
        library_hk,
        hash_diff
    from
        {{ this }}
    {% endif %}

),

transformed as (

    select
        library_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'metadata_manager') as record_source,
        hash_diff,
        orcabus_id,
        workflow,
        phenotype,
        type,
        assay,
        quality
    from
        encoded
    {% if is_incremental() %}
    where
        library_hk in (select library_hk from differentiated)
    {% endif %}

),

final as (

    select
        cast(library_hk as char(64)) as library_hk,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(hash_diff as char(64)) as hash_diff,
        cast(orcabus_id as varchar(255)) as orcabus_id,
        cast(workflow as varchar(255)) as workflow,
        cast(phenotype as varchar(255)) as phenotype,
        cast(type as varchar(255)) as type,
        cast(assay as varchar(255)) as assay,
        cast(quality as varchar(255)) as quality
    from
        transformed

)

select * from final
