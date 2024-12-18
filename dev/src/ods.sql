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

CREATE TABLE IF NOT EXISTS orcavault.ods.metadata_manager_library
(
    orcabus_id         varchar not null
        primary key,
    library_id         varchar
        unique,
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
    orcabus_id         varchar not null
        primary key,
    sample_id          varchar
        unique,
    external_sample_id varchar,
    source             varchar
);

CREATE TABLE IF NOT EXISTS orcavault.ods.metadata_manager_individual
(
    orcabus_id    varchar not null
        primary key,
    individual_id varchar
        unique,
    source        varchar
);

CREATE TABLE IF NOT EXISTS orcavault.ods.metadata_manager_subject
(
    orcabus_id varchar not null
        primary key,
    subject_id varchar
        unique
);

CREATE TABLE IF NOT EXISTS orcavault.ods.metadata_manager_project
(
    orcabus_id  varchar not null
        primary key,
    project_id  varchar
        unique,
    name        varchar,
    description varchar
);

CREATE TABLE IF NOT EXISTS orcavault.ods.metadata_manager_contact
(
    orcabus_id  varchar not null
        primary key,
    contact_id  varchar
        unique,
    name        varchar,
    description varchar,
    email       varchar(254)
);
