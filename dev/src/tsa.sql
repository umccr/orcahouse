SELECT current_database();

-- create tsa schema
CREATE SCHEMA IF NOT EXISTS tsa AUTHORIZATION dev;
SET search_path TO tsa;

SELECT current_schema();

-- --

DROP FUNCTION IF EXISTS tsa.truncate_tables();

CREATE OR REPLACE FUNCTION tsa.truncate_tables()
    RETURNS void
    LANGUAGE 'sql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DO $$ DECLARE
    table_name text;
BEGIN
    FOR table_name IN (SELECT tablename FROM pg_tables WHERE schemaname='tsa') LOOP
        EXECUTE 'TRUNCATE TABLE tsa."' || table_name || '" CASCADE;';
    END LOOP;
END $$;
$BODY$;

ALTER FUNCTION tsa.truncate_tables() OWNER TO dev;

-- --

CREATE TABLE IF NOT EXISTS orcavault.tsa.spreadsheet_library_tracking_metadata
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
    sheet_name            varchar
);

CREATE TABLE IF NOT EXISTS orcavault.tsa.spreadsheet_google_lims
(
    illumina_id         varchar,
    run                 varchar,
    timestamp           varchar,
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
    sheet_name          varchar
);
