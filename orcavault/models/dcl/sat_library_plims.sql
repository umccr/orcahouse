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
        cast("timestamp" as date) as "timestamp",
        illumina_id,
        workflow,
        phenotype,
        type,
        assay,
        quality,
        source
    from
        {{ source('legacy', 'data_portal_limsrow') }}

),

cleaned as (

    select
        trim(regexp_replace(library_id, E'[\\n\\r]+', '', 'g')) as library_id,
        "timestamp",
        row_number() over (partition by library_id, "timestamp" order by "timestamp" desc, illumina_id desc) as rank,
        trim(regexp_replace(workflow, E'[\\n\\r]+', '', 'g')) as workflow,
        trim(regexp_replace(phenotype, E'[\\n\\r]+', '', 'g')) as phenotype,
        trim(regexp_replace(type, E'[\\n\\r]+', '', 'g')) as type,
        trim(regexp_replace(assay, E'[\\n\\r]+', '', 'g')) as assay,
        trim(regexp_replace(quality, E'[\\n\\r]+', '', 'g')) as quality,
        trim(regexp_replace(source, E'[\\n\\r]+', '', 'g')) as source
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
        and cast("timestamp" as timestamptz) + time '11:00' > ( select coalesce(max(load_datetime), '1900-01-01') as ldts from {{ this }} )
    {% endif %}

),

encoded as (

    select
        encode(sha256(cast(library_id as bytea)), 'hex') as library_hk,
        encode(sha256(concat("timestamp", workflow, phenotype, type, assay, quality, source)::bytea), 'hex') as hash_diff,
        "timestamp",
        workflow,
        phenotype,
        type,
        assay,
        quality,
        source
    from
        differentiated

),

transformed as (

    select
        library_hk,
        cast("timestamp" as timestamptz) + time '11:00' as load_datetime,
        (select 'data_portal_limsrow') as record_source,
        hash_diff,
        "timestamp",
        workflow,
        phenotype,
        type,
        assay,
        quality,
        source
    from
        encoded

),

final as (

    select
        cast(library_hk as char(64)) as library_hk,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(hash_diff as char(64)) as hash_diff,
        cast("timestamp" as date) as "timestamp",
        cast(workflow as varchar(255)) as workflow,
        cast(phenotype as varchar(255)) as phenotype,
        cast(type as varchar(255)) as type,
        cast(assay as varchar(255)) as assay,
        cast(quality as varchar(255)) as quality,
        cast(source as varchar(255)) as source
    from
        transformed

)

select * from final
