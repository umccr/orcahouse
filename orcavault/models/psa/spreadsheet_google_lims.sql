{{
    config(
        materialized='incremental'
    )
}}

with cutoff as (

    select coalesce(max(load_datetime), '1900-01-01') as ldts from {{ this }}

),

source as (

    select
        *
    from
        {{ source('tsa', 'spreadsheet_google_lims') }}

    {% if is_incremental() %}

    where cast("timestamp" as timestamptz) + time '11:00' > ( select ldts from cutoff )

    {% endif %}

),

cleaned as (

    select
        trim(regexp_replace(illumina_id, E'[\\n\\r]+', '', 'g')) as illumina_id,
        trim(regexp_replace(run, E'[\\n\\r]+', '', 'g')) as run,
        trim(regexp_replace("timestamp", E'[\\n\\r]+', '', 'g')) as "timestamp",
        trim(regexp_replace(subject_id, E'[\\n\\r]+', '', 'g')) as subject_id,
        trim(regexp_replace(sample_id, E'[\\n\\r]+', '', 'g')) as sample_id,
        trim(regexp_replace(library_id, E'[\\n\\r]+', '', 'g')) as library_id,
        trim(regexp_replace(external_subject_id, E'[\\n\\r]+', '', 'g')) as external_subject_id,
        trim(regexp_replace(external_sample_id, E'[\\n\\r]+', '', 'g')) as external_sample_id,
        trim(regexp_replace(external_library_id, E'[\\n\\r]+', '', 'g')) as external_library_id,
        trim(regexp_replace(sample_name, E'[\\n\\r]+', '', 'g')) as sample_name,
        trim(regexp_replace(project_owner, E'[\\n\\r]+', '', 'g')) as project_owner,
        trim(regexp_replace(project_name, E'[\\n\\r]+', '', 'g')) as project_name,
        trim(regexp_replace(project_custodian, E'[\\n\\r]+', '', 'g')) as project_custodian,
        trim(regexp_replace(type, E'[\\n\\r]+', '', 'g')) as type,
        trim(regexp_replace(assay, E'[\\n\\r]+', '', 'g')) as assay,
        trim(regexp_replace(override_cycles, E'[\\n\\r]+', '', 'g')) as override_cycles,
        trim(regexp_replace(phenotype, E'[\\n\\r]+', '', 'g')) as phenotype,
        trim(regexp_replace(source, E'[\\n\\r]+', '', 'g')) as source,
        trim(regexp_replace(quality, E'[\\n\\r]+', '', 'g')) as quality,
        trim(regexp_replace(topup, E'[\\n\\r]+', '', 'g')) as topup,
        trim(regexp_replace(secondary_analysis, E'[\\n\\r]+', '', 'g')) as secondary_analysis,
        trim(regexp_replace(workflow, E'[\\n\\r]+', '', 'g')) as workflow,
        trim(regexp_replace(tags, E'[\\n\\r]+', '', 'g')) as tags,
        trim(regexp_replace(fastq, E'[\\n\\r]+', '', 'g')) as fastq,
        trim(regexp_replace(number_fastqs, E'[\\n\\r]+', '', 'g')) as number_fastqs,
        trim(regexp_replace(results, E'[\\n\\r]+', '', 'g')) as results,
        trim(regexp_replace(trello, E'[\\n\\r]+', '', 'g')) as trello,
        trim(regexp_replace(notes, E'[\\n\\r]+', '', 'g')) as notes,
        trim(regexp_replace(todo, E'[\\n\\r]+', '', 'g')) as todo,
        trim(regexp_replace(sheet_name, E'[\\n\\r]+', '', 'g')) as sheet_name
    from
        source
    where
        coalesce
        (
            nullif(illumina_id, ''),
            nullif(run, ''),
            nullif("timestamp", ''),
            nullif(subject_id, ''),
            nullif(sample_id, ''),
            nullif(library_id, ''),
            nullif(external_subject_id, ''),
            nullif(external_sample_id, ''),
            nullif(external_library_id, ''),
            nullif(sample_name, ''),
            nullif(project_owner, ''),
            nullif(project_name, ''),
            nullif(project_custodian, ''),
            nullif(type, ''),
            nullif(assay, ''),
            nullif(override_cycles, ''),
            nullif(phenotype, ''),
            nullif(source, ''),
            nullif(quality, ''),
            nullif(topup, ''),
            nullif(secondary_analysis, ''),
            nullif(workflow, ''),
            nullif(tags, ''),
            nullif(fastq, ''),
            nullif(number_fastqs, ''),
            nullif(results, ''),
            nullif(trello, ''),
            nullif(notes, ''),
            nullif(todo, ''),
            nullif(sheet_name, '')
        ) is not null

),

transformed as (

    select
        illumina_id,
        cast(run as integer),
        cast("timestamp" as date) as "timestamp",
        subject_id,
        sample_id,
        library_id,
        external_subject_id,
        external_sample_id,
        external_library_id,
        sample_name,
        project_owner,
        project_name,
        project_custodian,
        type,
        assay,
        override_cycles,
        phenotype,
        source,
        quality,
        topup,
        secondary_analysis,
        workflow,
        tags,
        fastq,
        number_fastqs,
        results,
        trello,
        notes,
        todo,
        sheet_name,
        cast("timestamp" as timestamptz) + time '11:00' as load_datetime,
        (select 'Google_LIMS') as record_source
    from
        cleaned

),

final as (

    select * from transformed

)

select * from final
