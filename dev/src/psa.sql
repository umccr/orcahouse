SELECT current_database();

-- create psa schema
CREATE SCHEMA IF NOT EXISTS psa AUTHORIZATION dev;
SET search_path TO psa;

SELECT current_schema();

CREATE TABLE IF NOT EXISTS orcavault.psa.spreadsheet_library_tracking_metadata
(
    assay                 varchar,
    comments              varchar,
    coverage              varchar,
    experiment_id         varchar,
    external_sample_id    varchar,
    external_subject_id   varchar,
    library_id            varchar,
    override_cycles       varchar,
    phenotype             varchar,
    project_name          varchar,
    project_owner         varchar,
    qpcr_id               varchar,
    quality               varchar,
    run                   varchar,
    sample_id             varchar,
    sample_name           varchar,
    samplesheet_sample_id varchar,
    source                varchar,
    subject_id            varchar,
    truseq_index          varchar,
    type                  varchar,
    workflow              varchar,
    r_rna                 varchar,
    study                 varchar,
    sheet_name            varchar,
    load_datetime         timestamptz,
    record_source         varchar(255)
);

CREATE TABLE IF NOT EXISTS orcavault.psa.spreadsheet_google_lims
(
    illumina_id         varchar,
    run                 integer,
    timestamp           date,
    subject_id          varchar,
    sample_id           varchar,
    library_id          varchar,
    external_subject_id varchar,
    external_sample_id  varchar,
    external_library_id varchar,
    sample_name         varchar,
    project_owner       varchar,
    project_name        varchar,
    project_custodian   varchar,
    type                varchar,
    assay               varchar,
    override_cycles     varchar,
    phenotype           varchar,
    source              varchar,
    quality             varchar,
    topup               varchar,
    secondary_analysis  varchar,
    workflow            varchar,
    tags                varchar,
    fastq               varchar,
    number_fastqs       varchar,
    results             varchar,
    trello              varchar,
    notes               varchar,
    todo                varchar,
    sheet_name          varchar,
    load_datetime       timestamptz,
    record_source       varchar(255)
);

CREATE TABLE IF NOT EXISTS orcavault.psa.event__fastq_list_row_state_change
(
    event_id                            varchar,
    event_time                          varchar,
    orcabus_id                          varchar,
    status                              varchar,
    instrument_run_id                   varchar,
    library                             varchar,
    lane                                varchar,
    index                               varchar,
    is_valid                            varchar,
    readset_r1                          varchar,
    readset_r2                          varchar,
    platform                            varchar,
    center                              varchar,
    read_count                          varchar,
    base_count_est                      varchar,
    readset_r1_rawmd5                   varchar,
    readset_r1_gzbytes                  varchar,
    readset_r2_rawmd5                   varchar,
    readset_r2_gzbytes                  varchar,
    qc_insert_size_estimate             varchar,
    qc_raw_wgs_coverage_estimate        varchar,
    qc_r1Q20_fraction                   varchar,
    qc_r2Q20_fraction                   varchar,
    qc_r1Gc_fraction                    varchar,
    qc_r2Gc_fraction                    varchar,
    qc_duplication_fraction_estimate    varchar,
    load_datetime                       timestamptz,
    record_source                       varchar(255)
);

CREATE TABLE IF NOT EXISTS orcavault.psa.event__sequence_run_state_change
(
    event_id            varchar,
    event_time          varchar,
    orcabus_id          varchar,
    status              varchar,
    instrument_run_id   varchar,
    start_time          varchar,
    end_time            varchar,
    samplesheet_name    varchar,
    load_datetime       timestamptz,
    record_source       varchar(255)
);

CREATE TABLE IF NOT EXISTS orcavault.psa.event__sequence_run_library_linking_change
(
    event_id            varchar,
    event_time          varchar,
    orcabus_id          varchar,
    instrument_run_id   varchar,
    sequence_run_id     varchar,
    timestamp           varchar,
    libraries           jsonb,
    load_datetime       timestamptz,
    record_source       varchar(255)
);

CREATE TABLE IF NOT EXISTS orcavault.psa.event__workflow_run_state_change
(
    event_id            varchar,
    event_time          varchar,
    portal_run_id       varchar,
    status              varchar,
    state_timestamp     varchar,
    workflow_name       varchar,
    workflow_version    varchar,
    workflow_run_name   varchar,
    libraries           jsonb,
    load_datetime       timestamptz,
    record_source       varchar(255)
);

CREATE TABLE IF NOT EXISTS orcavault.psa.event__metadata_state_change_library
(
    event_id                varchar,
    event_time              varchar,
    orcabus_id              varchar,
    action                  varchar,
    library_id              varchar,
    phenotype               varchar,
    workflow                varchar,
    quality                 varchar,
    type                    varchar,
    assay                   varchar,
    coverage                varchar,
    override_cycles          varchar,
    sample_orcabus_id       varchar,
    subject_orcabus_id      varchar,
    load_datetime           timestamptz,
    record_source           varchar(255)
);
