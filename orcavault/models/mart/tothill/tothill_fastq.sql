{{
    config(
        indexes=[
            {'columns': ['sequencing_run_id'], 'type': 'btree'},
            {'columns': ['sequencing_run_date'], 'type': 'btree'},
            {'columns': ['portal_run_id'], 'type': 'btree'},
            {'columns': ['cohort_id'], 'type': 'btree'},
            {'columns': ['library_id'], 'type': 'btree'},
            {'columns': ['bucket'], 'type': 'btree'},
            {'columns': ['key'], 'type': 'btree'},
            {'columns': ['filename'], 'type': 'btree'},
            {'columns': ['format'], 'type': 'btree'},
            {'columns': ['size'], 'type': 'btree'},
            {'columns': ['storage_class'], 'type': 'btree'},
            {'columns': ['last_modified_date'], 'type': 'btree'},
        ]
    )
}}

with transformed as (

    select
        lims.sequencing_run_id as sequencing_run_id,
        fq.sequencing_run_date as sequencing_run_date,
        fq.portal_run_id,
        fq.cohort_id,
        fq.bucket as bucket,
        fq.key as "key",
        lims.library_id as library_id,
        fq.filename as filename,
        fq.format as format,
        fq.size as "size",
        fq.storage_class as storage_class,
        fq.e_tag as e_tag,
        fq.last_modified_date as last_modified_date
    from {{ ref('fastq') }} fq
        join {{ ref('tothill_lims') }} lims on lims.library_id = fq.library_id and lims.sequencing_run_id = fq.sequencing_run_id

),

final as (

    select
        cast(sequencing_run_id as varchar(255)) as sequencing_run_id,
        cast(sequencing_run_date as date) as sequencing_run_date,
        cast(portal_run_id as varchar(255)) as portal_run_id,
        cast(cohort_id as varchar(255)) as cohort_id,
        cast(bucket as varchar(255)) as bucket,
        cast("key" as text) as "key",
        cast(library_id as varchar(255)) as library_id,
        cast(filename as text) as filename,
        cast(format as varchar(255)) as format,
        cast("size" as bigint) as "size",
        cast(storage_class as varchar(255)) as storage_class,
        cast(e_tag as varchar(255)) as e_tag,
        cast(last_modified_date as timestamptz) as last_modified_date
    from
        transformed
    order by sequencing_run_date desc nulls last, library_id desc

)

select * from final
