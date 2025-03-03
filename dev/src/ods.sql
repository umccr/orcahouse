SELECT current_database();

-- create ods schema
CREATE SCHEMA IF NOT EXISTS ods AUTHORIZATION dev;
SET search_path TO ods;

SELECT current_schema();

CREATE TABLE IF NOT EXISTS orcavault.ods.data_portal_labmetadata
(
    id                  bigint       not null,
    library_id          varchar(255) not null,
    sample_name         varchar(255),
    sample_id           varchar(255) not null,
    external_sample_id  varchar(255),
    subject_id          varchar(255),
    external_subject_id varchar(255),
    phenotype           varchar(255) not null,
    quality             varchar(255) not null,
    source              varchar(255) not null,
    project_name        varchar(255),
    project_owner       varchar(255),
    experiment_id       varchar(255),
    type                varchar(255) not null,
    assay               varchar(255) not null,
    override_cycles     varchar(255),
    workflow            varchar(255) not null,
    coverage            varchar(255),
    truseqindex         varchar(255)
);

CREATE TABLE IF NOT EXISTS orcavault.ods.data_portal_limsrow
(
    id                  bigint       not null,
    illumina_id         varchar(255) not null,
    run                 integer      not null,
    timestamp           date         not null,
    sample_id           varchar(255) not null,
    sample_name         varchar(255),
    subject_id          varchar(255),
    type                varchar(255),
    phenotype           varchar(255),
    source              varchar(255),
    quality             varchar(255),
    secondary_analysis  varchar(255),
    fastq               text,
    number_fastqs       varchar(255),
    results             text,
    todo                varchar(255),
    trello              text,
    notes               text,
    assay               varchar(255),
    external_library_id varchar(255),
    external_sample_id  varchar(255),
    external_subject_id varchar(255),
    library_id          varchar(255) not null,
    project_name        varchar(255),
    project_owner       varchar(255),
    topup               varchar(255),
    override_cycles     varchar(255),
    workflow            varchar(255)
);

CREATE TABLE IF NOT EXISTS orcavault.ods.data_portal_sequence
(
    id                bigint       not null,
    instrument_run_id varchar(255) not null,
    run_id            varchar(255) not null,
    sample_sheet_name varchar(255) not null,
    gds_folder_path   varchar(255) not null,
    gds_volume_name   varchar(255) not null,
    reagent_barcode   varchar(255) not null,
    flowcell_barcode  varchar(255) not null,
    status            varchar(255) not null,
    start_time        timestamp    not null,
    end_time          timestamp
);

CREATE TABLE IF NOT EXISTS orcavault.ods.data_portal_sequencerun
(
    id                   bigint       not null,
    run_id               varchar(255) not null,
    date_modified        timestamp    not null,
    status               varchar(255) not null,
    gds_folder_path      text         not null,
    gds_volume_name      text         not null,
    reagent_barcode      varchar(255) not null,
    v1pre3_id            varchar(255) not null,
    acl                  text         not null,
    flowcell_barcode     varchar(255) not null,
    sample_sheet_name    varchar(255) not null,
    api_url              text         not null,
    name                 varchar(255) not null,
    instrument_run_id    varchar(255) not null,
    msg_attr_action      varchar(255) not null,
    msg_attr_action_type varchar(255) not null,
    msg_attr_action_date timestamp    not null,
    msg_attr_produced_by varchar(255) not null
);

CREATE TABLE IF NOT EXISTS orcavault.ods.data_portal_libraryrun
(
    id                 bigint       not null,
    library_id         varchar(255) not null,
    instrument_run_id  varchar(255) not null,
    run_id             varchar(255) not null,
    lane               integer      not null,
    override_cycles    varchar(255) not null,
    coverage_yield     varchar(255),
    qc_pass            smallint,
    qc_status          varchar(255),
    valid_for_analysis smallint
);

CREATE TABLE IF NOT EXISTS orcavault.ods.data_portal_libraryrun_workflows
(
    id            bigint not null,
    libraryrun_id bigint not null,
    workflow_id   bigint not null
);

CREATE TABLE IF NOT EXISTS orcavault.ods.data_portal_workflow
(
    id              bigint       not null,
    wfr_name        text,
    type_name       varchar(255) not null,
    wfr_id          varchar(255),
    wfl_id          varchar(255),
    wfv_id          varchar(255),
    version         varchar(255),
    input           text         not null,
    start           timestamp    not null,
    output          text,
    "end"           timestamp,
    end_status      varchar(255),
    notified        smallint,
    sequence_run_id bigint,
    batch_run_id    bigint,
    portal_run_id   varchar(255) not null
);

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
    orcabus_id        varchar                  not null,
    instrument_run_id varchar(255)             not null,
    run_volume_name   text                     not null,
    run_folder_path   text,
    run_data_uri      text                     not null,
    status            varchar(255)             not null,
    start_time        timestamp with time zone not null,
    end_time          timestamp with time zone,
    reagent_barcode   varchar(255),
    flowcell_barcode  varchar(255),
    sample_sheet_name varchar(255),
    sequence_run_id   varchar(255),
    sequence_run_name varchar(255),
    v1pre3_id         varchar(255),
    ica_project_id    varchar(255),
    api_url           text
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

CREATE TABLE IF NOT EXISTS orcavault.ods.data_portal_s3object
(
    id                 bigint       not null,
    bucket             varchar(255) not null,
    key                text         not null,
    size               bigint       not null,
    last_modified_date timestamp    not null,
    e_tag              varchar(255) not null,
    unique_hash        varchar(64)  not null
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
