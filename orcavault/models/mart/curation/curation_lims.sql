{{
    config(
        indexes=[
            {'columns': ['sequencing_run_id'], 'type': 'btree'},
            {'columns': ['sequencing_run_date'], 'type': 'btree'},
            {'columns': ['library_id'], 'type': 'btree'},
            {'columns': ['internal_subject_id'], 'type': 'btree'},
            {'columns': ['external_subject_id'], 'type': 'btree'},
            {'columns': ['sample_id'], 'type': 'btree'},
            {'columns': ['external_sample_id'], 'type': 'btree'},
            {'columns': ['experiment_id'], 'type': 'btree'},
            {'columns': ['project_id'], 'type': 'btree'},
            {'columns': ['owner_id'], 'type': 'btree'},
            {'columns': ['workflow'], 'type': 'btree'},
            {'columns': ['phenotype'], 'type': 'btree'},
            {'columns': ['type'], 'type': 'btree'},
            {'columns': ['assay'], 'type': 'btree'},
            {'columns': ['quality'], 'type': 'btree'},
            {'columns': ['source'], 'type': 'btree'},
            {'columns': ['load_datetime'], 'type': 'btree'},
        ]
    )
}}

with transformed as (

    select
        *
    from
        {{ ref('lims') }}
    where
        sequencing_run_id is not null
        and type is not null
        and type not in ('10X', 'BiModal', 'exome', 'Exome', 'MeDIP', 'Metagenm', 'MethylSeq')
        and assay is not null
        and assay not like '%10X%'
        and assay not in ('BM-5L', 'BM-6L', 'CRISPR', 'MeDIP', 'Takara')
        and workflow in ('research', 'clinical', 'control', 'manual')
),

final as (

    select
        cast(sequencing_run_id as varchar(255)) as sequencing_run_id,
        cast(sequencing_run_date as date) as sequencing_run_date,
        cast(library_id as varchar(255)) as library_id,
        cast(internal_subject_id as varchar(255)) as internal_subject_id,
        cast(external_subject_id as varchar(255)) as external_subject_id,
        cast(sample_id as varchar(255)) as sample_id,
        cast(external_sample_id as varchar(255)) as external_sample_id,
        cast(experiment_id as varchar(255)) as experiment_id,
        cast(project_id as varchar(255)) as project_id,
        cast(owner_id as varchar(255)) as owner_id,
        cast(workflow as varchar(255)) as workflow,
        cast(phenotype as varchar(255)) as phenotype,
        cast(type as varchar(255)) as type,
        cast(assay as varchar(255)) as assay,
        cast(quality as varchar(255)) as quality,
        cast(source as varchar(255)) as source,
        cast(truseq_index as varchar(255)) as truseq_index,
        cast(load_datetime as timestamptz) as load_datetime
    from
        transformed
    order by sequencing_run_date desc nulls last, library_id desc

)

select * from final
