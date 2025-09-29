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
        owner_id = 'Grimmond'
        and project_id in (
            select
                distinct prj.project_id
            from
                {{ ref('hub_project') }} prj
                    join {{ ref('link_project_ownership') }} lnk on prj.project_hk = lnk.project_hk
                    join {{ ref('hub_owner') }} owner on lnk.owner_hk = owner.owner_hk
            where
                owner.owner_id = 'Grimmond'
        )

),

final as (

    select
        cast(sequencing_run_id as varchar(255)) as sequencing_run_id,
        cast(sequencing_run_date as date) as sequencing_run_date,
        cast(library_id as varchar(255)) as library_id,
        cast(alias_library_id as varchar(255)) as alias_library_id,
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
