{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail'
    )
}}

with source as (

    select
        portal_run_id,
        library_id,
        chrom,
        pos,
        ref,
        alt,
        dp,
        af,
        filter_status,
        variant_emitted
    from
        {{ source('psa', 'event__variant_monitoring_result') }}

),

encoded as (

    select
        encode(sha256(concat(
            encode(sha256(cast(portal_run_id as bytea)), 'hex'),
            encode(sha256(cast(library_id as bytea)), 'hex')
        )::bytea), 'hex') as library_workflow_run_hk,
        encode(sha256(concat(chrom, pos, ref, alt, dp, af, filter_status, variant_emitted)::bytea), 'hex') as hash_diff,
        chrom,
        pos,
        ref,
        alt,
        dp,
        af,
        filter_status,
        variant_emitted
    from
        source

),

differentiated as (

    select
        library_workflow_run_hk,
        hash_diff
    from
        encoded
    {% if is_incremental() %}
    except
    select
        library_workflow_run_hk,
        hash_diff
    from
        {{ this }}
    {% endif %}

),

transformed as (

    select
        library_workflow_run_hk,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'psa.event__variant_monitoring_result') as record_source,
        hash_diff,
        chrom,
        pos,
        ref,
        alt,
        dp,
        af,
        filter_status,
        variant_emitted
    from
        encoded
    {% if is_incremental() %}
    where
        (library_workflow_run_hk, hash_diff) in (select library_workflow_run_hk, hash_diff from differentiated)
    {% endif %}

),

final as (

    select
        cast(library_workflow_run_hk as char(64))  as library_workflow_run_hk,
        cast(load_datetime as timestamptz)          as load_datetime,
        cast(record_source as varchar(255))         as record_source,
        cast(hash_diff as char(64))                 as hash_diff,
        cast(chrom as varchar(255))                 as chrom,
        cast(pos as integer)                        as pos,
        cast(ref as varchar(255))                   as ref,
        cast(alt as varchar(255))                   as alt,
        cast(dp as integer)                         as dp,
        cast(af as double precision)                as af,
        cast(filter_status as varchar(255))         as filter_status,
        cast(variant_emitted as boolean)            as variant_emitted
    from
        transformed

)

select * from final
