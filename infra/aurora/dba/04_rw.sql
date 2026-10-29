-- create read-write db user for the mart reverse ETL

-- NOTE:
-- We are using "IAM database authentication", as for dbuser_ro (02_ro.sql).
-- No database password needs to be set.
-- The OrcaGlue `spreadsheet-mart-tables` Glue job replaces the `mart` tables from the OrcaVault mart CSV unload.
-- It runs in the UomPrimaryVpc private subnets through a Glue network connection. Its Glue role (rds-db:connect)
-- generates a short-lived auth token per connection, to login as this user over TLS.
-- https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/UsingWithRDS.IAMDBAuth.html
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

-- Step 2: Allow the user to replace the existing mart tables.
-- MAINTAIN allows ANALYZE after a load.
grant usage on schema "mart" to dbuser_rw;
grant select, insert, truncate, maintain on all tables in schema "mart" to dbuser_rw;

-- Step 3: Allow the same on the mart tables that sadmin creates later (the OrcaGlue job/init.sql).
alter default privileges for role sadmin in schema "mart" grant select, insert, truncate, maintain on tables to dbuser_rw;


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

select has_schema_privilege(
    'dbuser_rw',
    'mart',
    'usage'
) as can_use_schema;
-- expect `true`

-- After the OrcaGlue job/init.sql has created the tables:
select
    has_table_privilege('dbuser_rw', 'mart.lims', 'insert') as can_insert,
    has_table_privilege('dbuser_rw', 'mart.lims', 'truncate') as can_truncate,
    has_table_privilege('dbuser_rw', 'mart.lims', 'maintain') as can_maintain;
-- expect `true`, `true`, `true`
