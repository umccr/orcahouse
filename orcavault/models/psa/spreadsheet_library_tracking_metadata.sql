{{
    config(
        materialized='incremental'
    )
}}

with source as (

    select * from {{ source('tsa', 'spreadsheet_library_tracking_metadata') }}

),

cleaned as (

    select
        trim(regexp_replace(assay, E'[\\n\\r]+', '', 'g')) as assay,
        trim(regexp_replace(comments, E'[\\n\\r]+', '', 'g')) as comments,
        trim(regexp_replace(coverage, E'[\\n\\r]+', '', 'g')) as coverage,
        trim(regexp_replace(experiment_id, E'[\\n\\r]+', '', 'g')) as experiment_id,
        trim(regexp_replace(external_sample_id, E'[\\n\\r]+', '', 'g')) as external_sample_id,
        trim(regexp_replace(external_subject_id, E'[\\n\\r]+', '', 'g')) as external_subject_id,
        trim(regexp_replace(library_id, E'[\\n\\r]+', '', 'g')) as library_id,
        trim(regexp_replace(override_cycles, E'[\\n\\r]+', '', 'g')) as override_cycles,
        trim(regexp_replace(phenotype, E'[\\n\\r]+', '', 'g')) as phenotype,
        trim(regexp_replace(project_name, E'[\\n\\r]+', '', 'g')) as project_name,
        trim(regexp_replace(project_owner, E'[\\n\\r]+', '', 'g')) as project_owner,
        trim(regexp_replace(qpcr_id, E'[\\n\\r]+', '', 'g')) as qpcr_id,
        trim(regexp_replace(quality, E'[\\n\\r]+', '', 'g')) as quality,
        trim(regexp_replace(run, E'[\\n\\r]+', '', 'g')) as run,
        trim(regexp_replace(sample_id, E'[\\n\\r]+', '', 'g')) as sample_id,
        trim(regexp_replace(sample_name, E'[\\n\\r]+', '', 'g')) as sample_name,
        trim(regexp_replace(samplesheet_sample_id, E'[\\n\\r]+', '', 'g')) as samplesheet_sample_id,
        trim(regexp_replace(source, E'[\\n\\r]+', '', 'g')) as source,
        trim(regexp_replace(subject_id, E'[\\n\\r]+', '', 'g')) as subject_id,
        trim(regexp_replace(truseq_index, E'[\\n\\r]+', '', 'g')) as truseq_index,
        trim(regexp_replace(type, E'[\\n\\r]+', '', 'g')) as type,
        trim(regexp_replace(workflow, E'[\\n\\r]+', '', 'g')) as workflow,
        trim(regexp_replace(r_rna, E'[\\n\\r]+', '', 'g')) as r_rna,
        trim(regexp_replace(study, E'[\\n\\r]+', '', 'g')) as study,
        trim(regexp_replace(sheet_name, E'[\\n\\r]+', '', 'g')) as sheet_name
    from
        source
    where
        coalesce
        (
            nullif(assay, ''),
            nullif(comments, ''),
            nullif(coverage, ''),
            nullif(experiment_id, ''),
            nullif(external_sample_id, ''),
            nullif(external_subject_id, ''),
            nullif(library_id, ''),
            nullif(override_cycles, ''),
            nullif(phenotype, ''),
            nullif(project_name, ''),
            nullif(project_owner, ''),
            nullif(qpcr_id, ''),
            nullif(quality, ''),
            nullif(run, ''),
            nullif(sample_id, ''),
            nullif(sample_name, ''),
            nullif(samplesheet_sample_id, ''),
            nullif(source, ''),
            nullif(subject_id, ''),
            nullif(truseq_index, ''),
            nullif(type, ''),
            nullif(workflow, ''),
            nullif(r_rna, ''),
            nullif(study, '')
        ) is not null

),

transformed as (

    select
        *
    from
        cleaned
    except
    select
        assay,
        comments,
        coverage,
        experiment_id,
        external_sample_id,
        external_subject_id,
        library_id,
        override_cycles,
        phenotype,
        project_name,
        project_owner,
        qpcr_id,
        quality,
        run,
        sample_id,
        sample_name,
        samplesheet_sample_id,
        source,
        subject_id,
        truseq_index,
        type,
        workflow,
        r_rna,
        study,
        sheet_name
    from
        {{ this }}

),

final as (

    select
        *,
        cast('{{ run_started_at }}' as timestamptz) as load_datetime,
        (select 'UMCCR_Library_Tracking_MetaData') as record_source
    from
        transformed

)

select * from final
