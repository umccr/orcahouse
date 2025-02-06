{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail'
    )
}}

with source as (

    select distinct
        record_source,
        library_id,
        workflow,
        phenotype,
        type,
        assay,
        quality,
        source,
        truseq_index
    from
        {{ ref('spreadsheet_library_tracking_metadata') }}

),

cleaned as (

    select
        record_source,
        row_number() over (partition by library_id order by phenotype) as rank,
        trim(regexp_replace(library_id, E'[\\n\\r]+', '', 'g')) as library_id,
        trim(regexp_replace(workflow, E'[\\n\\r]+', '', 'g')) as workflow,
        trim(regexp_replace(phenotype, E'[\\n\\r]+', '', 'g')) as phenotype,
        trim(regexp_replace(type, E'[\\n\\r]+', '', 'g')) as type,
        trim(regexp_replace(assay, E'[\\n\\r]+', '', 'g')) as assay,
        trim(regexp_replace(quality, E'[\\n\\r]+', '', 'g')) as quality,
        trim(regexp_replace(source, E'[\\n\\r]+', '', 'g')) as source,
        trim(regexp_replace(truseq_index, E'[\\n\\r]+', '', 'g')) as truseq_index
    from
        source
    where
        library_id is not null or library_id <> ''

),

encoded as (

    select
        record_source,
        encode(sha256(cast(library_id as bytea)), 'hex') as library_hk,
        encode(sha256(concat(workflow, phenotype, type, assay, quality, source, truseq_index)::bytea), 'hex') as hash_diff,
        workflow,
        phenotype,
        type,
        assay,
        quality,
        source,
        truseq_index
    from
        cleaned
    where
        rank = 1

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
        record_source,
        hash_diff,
        workflow,
        phenotype,
        type,
        assay,
        quality,
        source,
        truseq_index
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
        cast(workflow as varchar(255)) as workflow,
        cast(phenotype as varchar(255)) as phenotype,
        cast(type as varchar(255)) as type,
        cast(assay as varchar(255)) as assay,
        cast(quality as varchar(255)) as quality,
        cast(source as varchar(255)) as source,
        cast(truseq_index as varchar(255)) as truseq_index
    from
        transformed

)

select * from final
