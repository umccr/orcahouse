-- create read-write db user for the mart reverse ETL

-- NOTE:
-- The OrcaGlue `spreadsheet-mart-tables` Glue job replaces the `mart` tables from the OrcaVault mart CSV unload.
-- It calls the RDS Data API, which login with a database password from AWS Secrets Manager.
-- The Data API doesn't support IAM database authentication. So, unlike dbuser_ro, this user has a password, and must NOT be granted rds_iam, because an rds_iam member can only login with an IAM auth token.
-- https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/data-api.html
--
-- Why the Data API with a secret (MVP choice): the cluster is private and OrcaGlue jobs run outside the VPC.
-- IAM auth needs a direct connection: for Glue, a VPC connection plus egress for the job's PyPI packages.
-- The Data API needs no network change, and the job only sends SQL; Aurora reads the CSV from S3 itself.
-- Revisit IAM auth if OrcaGlue gets VPC access.
--
-- Run as the master user (sadmin) in the orcanexus database, once per environment.
-- Replace `dev` with the environment.
--
-- 1. Create the secret, with a generated password:
--
--    aws secretsmanager create-secret \
--      --name orcanexus/dev/dbuser_rw \
--      --description "orcanexus-dev dbuser_rw login for the OrcaGlue spreadsheet-mart-tables Data API calls" \
--      --secret-string "$(python3 -c 'import json, secrets; print(json.dumps({"engine": "postgres", "username": "dbuser_rw", "password": secrets.token_urlsafe(32), "dbname": "orcanexus"}))')"
--
-- 2. In psql, set the rw_password variable from the secret, then run this script:
--
--    \set rw_password `aws secretsmanager get-secret-value --secret-id orcanexus/dev/dbuser_rw --query SecretString --output text | python3 -c 'import json, sys; print(json.load(sys.stdin)["password"])'`
--    \i 04_rw.sql
--
--    Without psql, e.g. in the RDS Query Editor, put the password in the `create role` statement instead.

create role dbuser_rw with
    login
    nosuperuser
    nocreatedb
    nocreaterole
    inherit
    password :'rw_password';

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
-- expect true, false, true

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
