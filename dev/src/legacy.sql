SELECT current_database();

-- create legacy schema
CREATE SCHEMA IF NOT EXISTS legacy AUTHORIZATION dev;
SET search_path TO legacy;

SELECT current_schema();

CREATE TABLE IF NOT EXISTS orcavault.legacy.data_portal_labmetadata
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

CREATE TABLE IF NOT EXISTS orcavault.legacy.data_portal_limsrow
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

CREATE TABLE IF NOT EXISTS orcavault.legacy.data_portal_sequence
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

CREATE TABLE IF NOT EXISTS orcavault.legacy.data_portal_sequencerun
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

CREATE TABLE IF NOT EXISTS orcavault.legacy.data_portal_libraryrun
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

CREATE TABLE IF NOT EXISTS orcavault.legacy.data_portal_libraryrun_workflows
(
    id            bigint not null,
    libraryrun_id bigint not null,
    workflow_id   bigint not null
);

CREATE TABLE IF NOT EXISTS orcavault.legacy.data_portal_workflow
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

CREATE TABLE IF NOT EXISTS orcavault.legacy.data_portal_s3object
(
    id                 bigint       not null,
    bucket             varchar(255) not null,
    key                text         not null,
    size               bigint       not null,
    last_modified_date timestamp    not null,
    e_tag              varchar(255) not null,
    unique_hash        varchar(64)  not null
);
