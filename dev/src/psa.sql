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