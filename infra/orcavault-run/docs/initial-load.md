# Initial load

These are the steps to set up an environment for the first time, including the
complete load and legacy sources. After setup, the daily schedule keeps the
warehouse up to date, see [Operating](../README.md#operating).

They're only for a new database that OrcaVault hasn't run on yet. Step 7 isn't
safe on an environment that's already set up.

The commands should be run from `infra/orcavault-run`, with `ENV` set to the
environment:

```bash
export AWS_PROFILE=unimelb-warehouse-prod-admin
ENV=dev
```

## 1. Create the image repository

Both environments use the same repository, so this is only done once.

```bash
terraform -chdir=account-wide init
terraform -chdir=account-wide apply
```

## 2. Build and push the image

Set the environment's `orcavault_release_ref` in its `release.auto.tfvars`, and
build and push its image, see
[Building an image](../README.md#building-an-image).

## 3. Apply the environment

```bash
terraform -chdir=environments/$ENV init
terraform -chdir=environments/$ENV apply -var schedule_enabled=false
```

The schedule starts a run every day after applying, so it's paused until the
initial load is done. A daily run before the legacy load would record the CDC
positions, after which step 7 isn't safe.

## 4. Grant the task's database user

dbt connects with Redshift IAM auth as the task role, so its database user is
`IAMR:orcavault-run-<env>-dbt-task-role`. It builds the `psa`, `dcl`, `mart`,
`seed`, `dbt_test__audit` and `ops` schemas. In dev, local builds use the
PowerUser which can also write to these schemas..

As a Redshift admin, in the environment's workgroup, before the first run, with
`<env>` replaced by `dev` or `prod`:

```sql
-- Created on first connection anyway, but the grants need it to exist.
create user "IAMR:orcavault-run-<env>-dbt-task-role" password disable;

-- dbt creates its schemas when they're missing.
grant create on database orcavault to "IAMR:orcavault-run-<env>-dbt-task-role";

-- The CDC and legacy sources.
grant usage on database awsdatacatalog to "IAMR:orcavault-run-<env>-dbt-task-role";

-- tsa is written by OrcaGlue and read by OrcaVault, including tables created later.
grant usage on schema tsa to "IAMR:orcavault-run-<env>-dbt-task-role";
grant select for tables in schema tsa to "IAMR:orcavault-run-<env>-dbt-task-role";
```

Every user that builds OrcaVault should get the `orcavault_builder` role below,
i.e. the task's user, and in dev the PowerUser user. dbt replaces a table model
by renaming the old table and dropping it, which needs `alter` and `drop` on a
table that another user has already created. The role's scoped permissions apply
to every table in a schema, so it doesn't matter which user owns which table.
The following should be applied to set this up:

```sql
-- The grants need the schemas to exist.
create schema if not exists psa;
create schema if not exists dcl;
create schema if not exists mart;
create schema if not exists seed;
create schema if not exists dbt_test__audit;
create schema if not exists ops;

create role orcavault_builder;
grant usage, create on schema psa, dcl, mart, seed, dbt_test__audit, ops to role orcavault_builder;
grant all for tables in schema psa to role orcavault_builder;
grant all for tables in schema dcl to role orcavault_builder;
grant all for tables in schema mart to role orcavault_builder;
grant all for tables in schema seed to role orcavault_builder;
grant all for tables in schema dbt_test__audit to role orcavault_builder;
grant all for tables in schema ops to role orcavault_builder;

grant role orcavault_builder to "IAMR:orcavault-run-<env>-dbt-task-role";
```

In dev, also grant it to the PowerUser user. The following query finds the power
user name:

```sql
select usename from pg_user where usename like 'IAMR:AWSReservedSSO_AWSPowerUserAccess%';
```

And then to grant:

```sql
grant role orcavault_builder to "IAMR:AWSReservedSSO_AWSPowerUserAccess_<suffix>";
```

## 5. Check the task

The task needs network access listed under
[Other considerations](../README.md#other-considerations). This checks the
deployed runner can get credentials and connect to Redshift. Expect exit code 0
on the task once it's finished.

```bash
eval "$(terraform -chdir=environments/$ENV output -json orcavault_run | jq -r .debug_command)"
```

## 6. Check that the Google LIMS sheet is loaded

The sheet is loaded into `tsa.spreadsheet__google_lims` separately, by
OrcaGlue's
[`spreadsheet-google-lims`](https://github.com/umccr/orcaglue/tree/main/spreadsheet-google-lims)
job. It has to be loaded before the legacy load:

```sql
select count(*) from tsa.spreadsheet__google_lims;
```

## 7. Load the legacy sources

The legacy sources are from before OrcaBus, e.g:

- The data portal, as the `legacy_data_portal_*` tables of the `data_portal`
  Glue database.
- The Google LIMS sheet, which OrcaGlue's `spreadsheet-google-lims` job loads
  into `tsa.spreadsheet__google_lims`.

These should be loaded as part of the initial setup by running:

```bash
ARN=$(terraform -chdir=environments/$ENV output -json orcavault_run | jq -r .state_machine_arn)
aws stepfunctions start-execution --state-machine-arn "$ARN" --input '{"args": ["run", "--full-refresh", "--vars", "{\"load_legacy\": true}"]}'
```

This is a `dbt run` of every model, where each model with a legacy source reads
it as well as its current sources. The exception is `hub_s3object`, which only
reads the data portal's objects, which is why we need the initial `run`.

## 8. Run the first full load

Start a run with Step Functions:

```bash
eval "$(terraform -chdir=environments/$ENV output -json orcavault_run | jq -r .start_run_command)"
```

No CDC positions are recorded yet, so this reads every commit, which also adds
the filemanager's objects to `hub_s3object`.

Don't run the legacy load again. With the CDC positions recorded, a legacy run
with `--full-refresh` would rebuild `hub_s3object` without the filemanager's
objects, and they wouldn't be read again.
