-- create read-write db user for the mart reverse ETL

-- NOTE:
-- We are using "IAM database authentication", as for dbuser_ro (02_ro.sql).
-- No database password needs to be set.
-- The OrcaGlue `spreadsheet-mart-tables` Glue job refreshes the `mart` tables from the OrcaVault mart CSV unload.
-- It runs in the UomPrimaryVpc private subnets through a Glue network connection. Its Glue role (rds-db:connect)
-- generates a short-lived auth token per connection, to login as this user over TLS.
-- https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/UsingWithRDS.IAMDBAuth.html
--
-- The job refreshes each table with a blue-green swap. It loads a shadow table in the `mart_stg` schema, then, in one
-- transaction, drops the `mart` table and moves the shadow table into `mart`. So this user creates and owns the `mart`
-- tables, and the job grants dbuser_ro select on each new table.
--
-- Run as the master user (sadmin) in the orcanexus database, once per environment.

create role dbuser_rw with
    login
    nosuperuser
    nocreatedb
    nocreaterole
    inherit;

-- Grant the special Aurora IAM role as we will use IAM database authentication
grant rds_iam to dbuser_rw;
grant connect on database orcanexus to dbuser_rw;

-- Step 1: Allow the user to import from S3 with the aws_s3 extension.
-- Only rds_superuser can execute it by default. The aws_commons functions are already public.
grant usage on schema aws_s3 to dbuser_rw;
grant execute on function aws_s3.table_import_from_s3(text, text, text, aws_commons._s3_uri_1, aws_commons._aws_credentials_1) to dbuser_rw;
grant execute on function aws_s3.table_import_from_s3(text, text, text, text, text, text, text, text, text) to dbuser_rw;

-- Step 2: Create the schema for the shadow tables. dbuser_ro has no access to it, so the API never sees a part loaded table.
create schema if not exists "mart_stg";

-- Step 3: Allow the user to create tables in both schemas.
-- It owns the tables it creates, which lets it drop a `mart` table and move a shadow table into `mart`.
grant usage, create on schema "mart" to dbuser_rw;
grant usage, create on schema "mart_stg" to dbuser_rw;


-- -- --


select
    rolcanlogin,
    pg_has_role('dbuser_rw', 'rds_iam', 'member') as has_rds_iam,
    has_database_privilege('dbuser_rw', 'orcanexus', 'connect') as can_connect
from pg_roles
where rolname = 'dbuser_rw';
-- expect `true`, `true`, `true`

select has_function_privilege(
    'dbuser_rw',
    'aws_s3.table_import_from_s3(text, text, text, aws_commons._s3_uri_1, aws_commons._aws_credentials_1)',
    'execute'
) as can_import;
-- expect `true`

select
    has_schema_privilege('dbuser_rw', 'mart', 'create') as can_create_in_mart,
    has_schema_privilege('dbuser_rw', 'mart_stg', 'create') as can_create_in_mart_stg,
    has_schema_privilege('dbuser_ro', 'mart_stg', 'usage') as ro_can_use_mart_stg;
-- expect `true`, `true`, `false`

-- After the first Glue job run:
select
    schemaname,
    tablename,
    tableowner,
    has_table_privilege('dbuser_ro', format('%I.%I', schemaname, tablename), 'select') as ro_can_select
from pg_tables
where schemaname in ('mart', 'mart_stg')
order by schemaname, tablename;
-- expect every `mart` table owned by `dbuser_rw`, with ro_can_select `true`, and no `mart_stg` table
