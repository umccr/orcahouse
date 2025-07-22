SELECT current_database();

-- create ods schema
CREATE SCHEMA IF NOT EXISTS ods AUTHORIZATION dev;
SET search_path TO ods;

SELECT current_schema();

CREATE TABLE IF NOT EXISTS orcavault.ods.workflow_manager_workflowrun
(
    orcabus_id        varchar      not null primary key,
    portal_run_id     varchar(255) not null unique,
    execution_id      varchar(255),
    workflow_run_name varchar(255),
    comment           varchar(255),
    analysis_run_id   varchar,
    workflow_id       varchar
);

CREATE TABLE IF NOT EXISTS orcavault.ods.workflow_manager_workflowruncomment
(
    orcabus_id      varchar                  not null primary key,
    comment         text                     not null,
    created_at      timestamp with time zone not null,
    created_by      varchar(255)             not null,
    updated_at      timestamp with time zone not null,
    is_deleted      boolean                  not null,
    workflow_run_id varchar                  not null
);

CREATE TABLE IF NOT EXISTS orcavault.ods.workflow_manager_workflow
(
    orcabus_id                   varchar      not null primary key,
    workflow_name                varchar(255) not null,
    workflow_version             varchar(255) not null,
    execution_engine             varchar(255) not null,
    execution_engine_pipeline_id varchar(255) not null
);

CREATE TABLE IF NOT EXISTS orcavault.ods.workflow_manager_state
(
    orcabus_id      varchar                  not null primary key,
    status          varchar(255)             not null,
    timestamp       timestamp with time zone not null,
    comment         varchar(255),
    payload_id      varchar,
    workflow_run_id varchar                  not null
);

CREATE TABLE IF NOT EXISTS orcavault.ods.workflow_manager_payload
(
    orcabus_id     varchar      not null primary key,
    payload_ref_id varchar(255) not null unique,
    version        varchar(255) not null,
    data           jsonb        not null
);

CREATE TABLE IF NOT EXISTS orcavault.ods.workflow_manager_library
(
    orcabus_id varchar      not null primary key,
    library_id varchar(255) not null
);

CREATE TABLE IF NOT EXISTS orcavault.ods.workflow_manager_libraryassociation
(
    orcabus_id       varchar                  not null primary key,
    association_date timestamp with time zone not null,
    status           varchar(255)             not null,
    library_id       varchar                  not null,
    workflow_run_id  varchar                  not null
);

CREATE TABLE IF NOT EXISTS orcavault.ods.sequence_run_manager_sequence
(
    orcabus_id        varchar(26)  not null primary key,
    instrument_run_id varchar(255),
    run_volume_name   text,
    run_folder_path   text,
    run_data_uri      text,
    status            varchar(255),
    start_time        timestamp with time zone,
    end_time          timestamp with time zone,
    reagent_barcode   varchar(255),
    flowcell_barcode  varchar(255),
    sample_sheet_name varchar(255) not null,
    sequence_run_id   varchar(255) not null,
    sequence_run_name varchar(255),
    v1pre3_id         varchar(255),
    ica_project_id    varchar(255),
    api_url           text,
    experiment_name   varchar(255)
);

CREATE TABLE IF NOT EXISTS orcavault.ods.sequence_run_manager_state
(
    orcabus_id  varchar(26)              not null primary key,
    status      varchar(255)             not null,
    timestamp   timestamp with time zone not null,
    comment     varchar(255),
    sequence_id varchar(26)              not null
);

CREATE TABLE IF NOT EXISTS orcavault.ods.sequence_run_manager_samplesheet
(
    orcabus_id            varchar(26)              not null primary key,
    sample_sheet_name     varchar(255)             not null,
    association_status    varchar(255)             not null,
    association_timestamp timestamp with time zone not null,
    sample_sheet_content  jsonb,
    sequence_id           varchar(26)              not null
);

CREATE TABLE IF NOT EXISTS orcavault.ods.sequence_run_manager_libraryassociation
(
    orcabus_id       varchar(26)              not null primary key,
    library_id       varchar(255)             not null,
    association_date timestamp with time zone not null,
    status           varchar(255)             not null,
    sequence_id      varchar(26)              not null
);

CREATE TABLE IF NOT EXISTS orcavault.ods.sequence_run_manager_comment
(
    orcabus_id  varchar(26)              not null primary key,
    comment     text                     not null,
    target_id   varchar(26)              not null,
    created_at  timestamp with time zone not null,
    created_by  varchar(255)             not null,
    updated_at  timestamp with time zone not null,
    is_deleted  boolean                  not null,
    target_type varchar(255)             not null
);

CREATE TABLE IF NOT EXISTS orcavault.ods.metadata_manager_library
(
    orcabus_id         varchar not null,
    library_id         varchar,
    phenotype          varchar,
    workflow           varchar,
    quality            varchar,
    type               varchar,
    assay              varchar,
    coverage           double precision,
    sample_orcabus_id  varchar,
    subject_orcabus_id varchar
);

CREATE TABLE IF NOT EXISTS orcavault.ods.metadata_manager_sample
(
    orcabus_id         varchar not null,
    sample_id          varchar,
    external_sample_id varchar,
    source             varchar
);

CREATE TABLE IF NOT EXISTS orcavault.ods.metadata_manager_individual
(
    orcabus_id    varchar not null,
    individual_id varchar,
    source        varchar
);

CREATE TABLE IF NOT EXISTS orcavault.ods.metadata_manager_subject
(
    orcabus_id varchar not null,
    subject_id varchar
);

CREATE TABLE IF NOT EXISTS orcavault.ods.metadata_manager_subjectindividuallink
(
    id                    bigint,
    individual_orcabus_id varchar not null,
    subject_orcabus_id    varchar not null
);

CREATE TABLE IF NOT EXISTS orcavault.ods.metadata_manager_project
(
    orcabus_id  varchar not null,
    project_id  varchar,
    name        varchar,
    description varchar
);

CREATE TABLE IF NOT EXISTS orcavault.ods.metadata_manager_libraryprojectlink
(
    id                 bigint,
    library_orcabus_id varchar not null,
    project_orcabus_id varchar not null
);

CREATE TABLE IF NOT EXISTS orcavault.ods.metadata_manager_contact
(
    orcabus_id  varchar not null,
    contact_id  varchar,
    name        varchar,
    description varchar,
    email       varchar(254)
);

CREATE TABLE IF NOT EXISTS orcavault.ods.metadata_manager_projectcontactlink
(
    id                 bigint,
    contact_orcabus_id varchar not null,
    project_orcabus_id varchar not null
);

CREATE TABLE IF NOT EXISTS orcavault.ods.metadata_manager_historicalcontact
(
    orcabus_id            varchar                  not null,
    contact_id            varchar,
    name                  varchar,
    description           varchar,
    email                 varchar(254),
    history_id            integer primary key,
    history_date          timestamp with time zone not null,
    history_change_reason varchar(100),
    history_type          varchar(1)               not null,
    history_user_id       varchar
);

CREATE TABLE IF NOT EXISTS orcavault.ods.metadata_manager_historicalindividual
(
    orcabus_id            varchar                  not null,
    individual_id         varchar,
    source                varchar,
    history_id            integer primary key,
    history_date          timestamp with time zone not null,
    history_change_reason varchar(100),
    history_type          varchar(1)               not null,
    history_user_id       varchar
);

CREATE TABLE IF NOT EXISTS orcavault.ods.metadata_manager_historicallibrary
(
    orcabus_id            varchar                  not null,
    library_id            varchar,
    phenotype             varchar,
    workflow              varchar,
    quality               varchar,
    type                  varchar,
    assay                 varchar,
    coverage              double precision,
    history_id            integer primary key,
    history_date          timestamp with time zone not null,
    history_change_reason varchar(100),
    history_type          varchar(1)               not null,
    sample_orcabus_id     varchar,
    subject_orcabus_id    varchar,
    history_user_id       varchar
);

CREATE TABLE IF NOT EXISTS orcavault.ods.metadata_manager_historicallibraryprojectlink
(
    id                 bigint  not null,
    m2m_history_id     integer primary key,
    history_id         integer not null,
    library_orcabus_id varchar,
    project_orcabus_id varchar
);

CREATE TABLE IF NOT EXISTS orcavault.ods.metadata_manager_historicalproject
(
    orcabus_id            varchar                  not null,
    project_id            varchar,
    name                  varchar,
    description           varchar,
    history_id            integer primary key,
    history_date          timestamp with time zone not null,
    history_change_reason varchar(100),
    history_type          varchar(1)               not null,
    history_user_id       varchar
);

CREATE TABLE IF NOT EXISTS orcavault.ods.metadata_manager_historicalprojectcontactlink
(
    id                 bigint  not null,
    m2m_history_id     integer primary key,
    contact_orcabus_id varchar,
    history_id         integer not null,
    project_orcabus_id varchar
);

CREATE TABLE IF NOT EXISTS orcavault.ods.metadata_manager_historicalsample
(
    orcabus_id            varchar                  not null,
    sample_id             varchar,
    external_sample_id    varchar,
    source                varchar,
    history_id            integer primary key,
    history_date          timestamp with time zone not null,
    history_change_reason varchar(100),
    history_type          varchar(1)               not null,
    history_user_id       varchar
);

CREATE TABLE IF NOT EXISTS orcavault.ods.metadata_manager_historicalsubject
(
    orcabus_id            varchar                  not null,
    subject_id            varchar,
    history_id            integer primary key,
    history_date          timestamp with time zone not null,
    history_change_reason varchar(100),
    history_type          varchar(1)               not null,
    history_user_id       varchar
);

CREATE TABLE IF NOT EXISTS orcavault.ods.metadata_manager_historicalsubjectindividuallink
(
    id                    bigint  not null,
    m2m_history_id        integer primary key,
    history_id            integer not null,
    individual_orcabus_id varchar,
    subject_orcabus_id    varchar
);

CREATE TYPE archive_status AS ENUM ('ArchiveAccess', 'DeepArchiveAccess');
CREATE TYPE crawl_status AS ENUM ('InProgress', 'Completed', 'Failed');
CREATE TYPE event_type AS ENUM ('Created', 'Deleted', 'Other');
CREATE TYPE reason AS ENUM ('CreatedPut', 'CreatedPost', 'CreatedCopy', 'CreatedCompleteMultipartUpload', 'Deleted', 'DeletedLifecycle', 'Restored', 'RestoreExpired', 'StorageClassChanged', 'Crawl', 'Unknown', 'CrawlRestored');
CREATE TYPE storage_class AS ENUM ('DeepArchive', 'Glacier', 'GlacierIr', 'IntelligentTiering', 'OnezoneIa', 'Outposts', 'ReducedRedundancy', 'Snow', 'Standard', 'StandardIa');

CREATE TABLE IF NOT EXISTS orcavault.ods.file_manager_s3_object
(
    s3_object_id            uuid                              not null primary key,
    event_type              event_type                        not null,
    bucket                  text                              not null,
    key                     text                              not null,
    version_id              text    default 'null'::text      not null,
    event_time              timestamp with time zone,
    size                    bigint,
    sha256                  text,
    last_modified_date      timestamp with time zone,
    e_tag                   text,
    storage_class           storage_class,
    sequencer               text,
    is_delete_marker        boolean default false             not null,
    number_duplicate_events bigint  default 0                 not null,
    attributes              jsonb,
    deleted_date            timestamp with time zone,
    deleted_sequencer       text,
    number_reordered        bigint  default 0                 not null,
    ingest_id               uuid,
    is_current_state        boolean default true              not null,
    reason                  reason  default 'Unknown'::reason not null,
    archive_status          archive_status,
    is_accessible           boolean
);
