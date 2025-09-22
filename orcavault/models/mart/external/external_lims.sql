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

        sqr.sequencing_run_id as sequencing_run_id,
        cast((regexp_match(sqr.sequencing_run_id, '(?:^)(\d{6})(?:_A\d{5}_\d{4}_[A-Z0-9]{10})'))[1] as date) as sequencing_run_date,
        lib.library_id as library_id,
        null as alias_library_id,
        int_sbj.internal_subject_id as internal_subject_id,
        ext_sbj.external_subject_id as external_subject_id,
        smp.sample_id as sample_id,
        ext_smp.external_sample_id as external_sample_id,
        expr.experiment_id as experiment_id,
        prj.project_id as project_id,
        owner.owner_id as owner_id,
        coalesce(sat.workflow, sat2.workflow) as workflow,
        coalesce(sat.phenotype, sat2.phenotype) as phenotype,
        coalesce(sat.type, sat2.type) as type,
        coalesce(sat.assay, sat2.assay) as assay,
        coalesce(sat.quality, sat2.quality) as quality,
        sat.source as source,
        sat.truseq_index as truseq_index,
        coalesce(sat.load_datetime, sat2.load_datetime) as load_datetime

    from

        {{ ref('hub_library') }} lib

            left join {{ ref('link_library_sequencing_run') }} lnk1 on lib.library_hk = lnk1.library_hk
            left join {{ ref('hub_sequencing_run') }} sqr on lnk1.sequencing_run_hk = sqr.sequencing_run_hk

            left join {{ ref('link_library_internal_subject') }} lnk2 on lib.library_hk = lnk2.library_hk
            left join {{ ref('hub_internal_subject') }} int_sbj on lnk2.internal_subject_hk = int_sbj.internal_subject_hk

            left join {{ ref('link_library_external_subject') }} lnk3 on lib.library_hk = lnk3.library_hk
            left join {{ ref('hub_external_subject') }} ext_sbj on lnk3.external_subject_hk = ext_sbj.external_subject_hk

            left join {{ ref('link_library_sample') }} lnk4 on lib.library_hk = lnk4.library_hk
            left join {{ ref('hub_sample') }} smp on lnk4.sample_hk = smp.sample_hk

            left join {{ ref('link_library_external_sample') }} lnk5 on lib.library_hk = lnk5.library_hk
            left join {{ ref('hub_external_sample') }} ext_smp on lnk5.external_sample_hk = ext_smp.external_sample_hk

            left join {{ ref('link_library_experiment') }} lnk6 on lib.library_hk = lnk6.library_hk
            left join {{ ref('hub_experiment') }} expr on lnk6.experiment_hk = expr.experiment_hk

            left join {{ ref('link_library_project') }} lnk7 on lib.library_hk = lnk7.library_hk
            left join {{ ref('hub_project') }} prj on lnk7.project_hk = prj.project_hk

            left join {{ ref('link_library_ownership') }} lnk8 on lib.library_hk = lnk8.library_hk
            left join {{ ref('hub_owner') }} owner on lnk8.owner_hk = owner.owner_hk

            left join {{ ref('sat_library_glab') }} sat on lib.library_hk = sat.library_hk
            left join {{ ref('sat_library_mm') }} sat2 on lib.library_hk = sat2.library_hk

),

filtered as (

    select
        *
    from
        transformed
    where
        library_id in ('LTGX240001', 'LTGX240002')
        or
        project_id in ('PDAC-HMF')

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
        filtered
    order by sequencing_run_date desc nulls last, library_id desc

)

select * from final
