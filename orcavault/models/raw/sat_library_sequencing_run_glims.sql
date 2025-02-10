{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        on_schema_change='fail'
    )
}}

with source as (

    select
        illumina_id as sequencing_run_id,
        library_id,
        record_source,
        cast("timestamp" as date) as "timestamp",
        run,
        override_cycles,
        secondary_analysis,
        number_fastqs,
        fastq,
        results,
        notes,
        trello
    from
        {{ ref('spreadsheet_google_lims') }}

),

cleaned as (

    select
        row_number() over (partition by library_id, "timestamp" order by "timestamp" desc, sequencing_run_id desc) as rank,
        sequencing_run_id,
        trim(regexp_replace(library_id, E'[\\n\\r]+', '', 'g')) as library_id,
        record_source,
        "timestamp",
        run,
        trim(regexp_replace(override_cycles, E'[\\n\\r]+', '', 'g')) as override_cycles,
        trim(regexp_replace(secondary_analysis, E'[\\n\\r]+', '', 'g')) as secondary_analysis,
        trim(regexp_replace(number_fastqs, E'[\\n\\r]+', '', 'g')) as number_fastqs,
        trim(regexp_replace(fastq, E'[\\n\\r]+', '', 'g')) as fastq,
        trim(regexp_replace(results, E'[\\n\\r]+', '', 'g')) as results,
        trim(regexp_replace(notes, E'[\\n\\r]+', '', 'g')) as notes,
        trim(regexp_replace(trello, E'[\\n\\r]+', '', 'g')) as trello
    from
        source
    where
        (library_id is not null or library_id <> '') and
        (sequencing_run_id is not null or sequencing_run_id <> '')

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
        encode(sha256(cast(sequencing_run_id as bytea)), 'hex') as sequencing_run_hk,
        encode(sha256(cast(library_id as bytea)), 'hex') as library_hk,
        record_source,
        encode(sha256(concat("timestamp", run, override_cycles, secondary_analysis, number_fastqs, fastq, results, notes, trello)::bytea), 'hex') as hash_diff,
        "timestamp",
        run,
        override_cycles,
        secondary_analysis,
        number_fastqs,
        fastq,
        results,
        notes,
        trello
    from
        differentiated

),

transformed as (

    select
        encode(sha256(concat(sequencing_run_hk, library_hk)::bytea), 'hex') as library_sequencing_run_hk,
        cast("timestamp" as timestamptz) + time '11:00' as load_datetime,
        record_source,
        hash_diff,
        "timestamp",
        run,
        override_cycles,
        secondary_analysis,
        number_fastqs,
        fastq,
        results,
        notes,
        trello
    from
        encoded

),

final as (

    select
        cast(library_sequencing_run_hk as char(64)) as library_sequencing_run_hk,
        cast(load_datetime as timestamptz) as load_datetime,
        cast(record_source as varchar(255)) as record_source,
        cast(hash_diff as char(64)) as hash_diff,
        cast("timestamp" as date) as "timestamp",
        cast(run as integer) as run,
        cast(override_cycles as varchar(255)) as override_cycles,
        cast(secondary_analysis as varchar(255)) as secondary_analysis,
        cast(number_fastqs as varchar(255)) as number_fastqs,
        cast(fastq as text) as fastq,
        cast(results as text) as results,
        cast(notes as text) as notes,
        cast(trello as text) as trello
    from
        transformed

)

select * from final
