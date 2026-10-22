-- create read-only db user

-- NOTE:
-- We are using "IAM database authentication".
-- No database password needs to be set.
-- Via an IAM role, we generate a time-gated, short-live auth token (that can treat it like as a database password) per connection.
-- https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/UsingWithRDS.IAMDBAuth.html

create role dbuser_ro with
    login
    nosuperuser
    nocreatedb
    nocreaterole
    inherit;

-- Grant the special Aurora IAM role as we will use IAM database authentication
grant rds_iam to dbuser_ro;
grant connect on database orcanexus to dbuser_ro;

-- Step 1: Allow the user to "see" the schema
grant usage on schema "mnt" to dbuser_ro;
grant usage on schema "mart" to dbuser_ro;
grant usage on schema "result" to dbuser_ro;

-- Step 2: Allow the user to read existing tables
grant select on all tables in schema "mnt" to dbuser_ro;
grant select on all tables in schema "mart" to dbuser_ro;
grant select on all tables in schema "result" to dbuser_ro;

-- Step 3: Allow the user to read future tables automatically
alter default privileges in schema "mnt" grant select on tables to dbuser_ro;
alter default privileges in schema "mart" grant select on tables to dbuser_ro;
alter default privileges in schema "result" grant select on tables to dbuser_ro;


-- -- --


select pg_has_role('dbuser_ro', 'rds_iam', 'member');
-- expect `true`

select rolcanlogin from pg_roles where rolname = 'dbuser_ro';
-- expect `true`

select
    rolcanlogin,
    rolinherit,
    pg_has_role('dbuser_ro', 'rds_iam', 'member') as has_rds_iam,
    pg_has_role('dbuser_ro', 'pg_read_all_data', 'member') as has_read_all_data,
    has_database_privilege('dbuser_ro', 'orcanexus', 'connect') as can_connect
from pg_roles
where rolname = 'dbuser_ro';

select
    rolname,
    rolcanlogin,
    rolinherit,
    rolpassword is not null as has_password
from pg_roles
where rolname = 'dbuser_ro';

select has_schema_privilege(
    'dbuser_ro',
    'mnt',
    'usage'
) as can_use_schema;

select has_table_privilege(
    'dbuser_ro',
    'mnt.lims',
    'select'
) as can_select;
