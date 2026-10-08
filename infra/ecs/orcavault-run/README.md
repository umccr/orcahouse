# OrcaVault daily run

Builds the [umccr/orcavault](https://github.com/umccr/orcavault) dbt project on
Redshift Serverless once a day.

```
EventBridge Scheduler, 03:00 Australia/Melbourne
  └─ Step Functions state machine orcavault-run
       1. CheckNoRunInProgress   fails if an OrcaVault dbt task is already running
       2. RunDbt                 ECS Fargate task running dbt build, and waits for it
  └─ SNS topic orcavault-run-alerts
       - a run failed, timed out or was stopped
       - no run has succeeded in the last 30 hours
```

This replaces `infra/ecs/legacy/orcavault-dbt`, which runs the retired
`orcahouse/orcavault` project against Aurora. That stack still has its own
daily schedule, and decommissioning it is a separate change.

## Why this design

- **dbt orders the work itself.** A single `dbt build` knows every model's
  dependencies, so the state machine doesn't need to model them. A state
  machine with one step per model would duplicate the DAG and drift from it.
- **ECS Fargate runs dbt.** A run can take longer than Lambda's 15 minutes, and
  a container pins the dbt version and project code in an image.
- **Step Functions runs the task.** It keeps a history of every run, stops the
  task at a timeout, checks that no other run is going, and emits an event when
  a run fails. Scheduling the task straight from EventBridge, as the old Aurora
  job does, gives none of the first three.
- **No Airflow.** MWAA would also work, but it is an always-on environment for
  what is a single daily job.

## What a run does

### Order and parallelism

dbt builds the models in dependency order, and up to `dbt_threads` independent
models at once (4 by default). More threads than the workgroup's RPU can serve
only queue in Redshift, so raise them together.

`dbt build` runs each model's tests straight after the model. A failing
error-severity test skips everything downstream of that model, so bad data
doesn't spread. Warn-severity tests only log. The unit tests are left out,
because they test the project code against fixtures, which is a job for CI.

### When some models fail

The run is reported as failed, and everything that could load does load.

- dbt exits non-zero, so the execution fails and an alert is sent.
- Models that succeeded stay loaded. Each model commits on its own.
- A failed model skips only the models that depend on it. Unrelated models
  still build, since there is no `--fail-fast`.
- The CDC positions in `ops.cdc_watermark` only move when every model succeeds.
  After a partial failure they stay put, and the next run rereads the same
  window. The models skip rows they already have, so the rereading is harmless,
  and the next successful run catches up by itself. See
  [docs/watermark-architecture.md](https://github.com/umccr/orcavault/blob/main/docs/watermark-architecture.md).

The trade-off is that one model that keeps failing holds every position back,
so each run rereads a bigger window until it's fixed. Fix failures within days,
not weeks.

A failed run is not retried. Whatever failed would most likely fail again, and
the next daily run covers it. Only failures to start the task, such as no
Fargate capacity, are retried.

### Overlapping runs

OrcaVault's incremental models assume runs don't overlap. Two things prevent it:

- `CheckNoRunInProgress` fails the execution if an OrcaVault dbt task is
  already running, however it was started.
- A run is stopped after `run_timeout_hours` (4 by default), well before the
  next scheduled run.

Two executions started within the same second could both pass the check. That
is unlikely enough to accept.

### Timing relative to upstream

The run starts at 03:00 Melbourne time. That is after the OrcaGlue TSA jobs
(13:10 UTC) and the OrcaBus Glue crawlers (15:00 UTC), so most of the day's
data is visible. It doesn't wait for them. Whatever isn't visible yet is picked
up by the next run, because the CDC positions only move past commits that the
run could see.

## First-time setup

### 1. Build and push the image

`orcavault_release_ref` is the orcavault tag or commit the image is built from,
and its ECR tag. Tags are immutable. Pin a release tag or commit, never a
branch, so that the code behind any load can be found again.

The repository is created by the stack, so on the very first deploy create it
first:

```bash
terraform apply -target=aws_ecr_repository.dbt -var orcavault_release_ref=v1.2.3
```

Then build and push:

```bash
REF=v1.2.3
REPO=$(terraform output -raw ecr_repository_url)
aws ecr get-login-password | docker login --username AWS --password-stdin "${REPO%%/*}"
docker buildx build --platform linux/arm64 --build-arg "ORCAVAULT_REF=$REF" -t "$REPO:$REF" --push docker/
```

The build runs `dbt parse`, so a project that doesn't parse fails here rather
than at 3am.

### 2. Apply

```bash
export AWS_PROFILE=unimelb-warehouse-prod-admin
terraform init
terraform apply -var orcavault_release_ref=v1.2.3
```

The applying role must be a Lake Formation admin, because `lakeformation.tf`
grants the task role read on the CDC Glue databases.

### 3. Grant the task's database user

dbt connects with Redshift IAM auth as the task role, so its database user is
`IAMR:orcavault-run-dbt-task-role` (`terraform output -raw dbt_task_db_identity`).
It creates and owns everything OrcaVault writes: the `psa`, `dcl`, `mart`,
`seed`, `dbt_test__audit` and `ops` schemas.

As a Redshift admin, before the first run:

```sql
-- Created on first connection anyway, but the grants need it to exist.
create user "IAMR:orcavault-run-dbt-task-role" password disable;

-- dbt creates its schemas when they're missing.
grant create on database orcavault to "IAMR:orcavault-run-dbt-task-role";

-- The CDC sources.
grant usage on database awsdatacatalog to "IAMR:orcavault-run-dbt-task-role";

-- tsa is written by OrcaGlue and read by OrcaVault.
grant usage on schema tsa to "IAMR:orcavault-run-dbt-task-role";
grant select on all tables in schema tsa to "IAMR:orcavault-run-dbt-task-role";
-- Only needed if OrcaGlue creates new tsa tables rather than reloading them.
alter default privileges for user "<orcaglue-user>" in schema tsa
    grant select on tables to "IAMR:orcavault-run-dbt-task-role";
```

**If OrcaVault has already been built here as another user**, that user owns
its schemas and tables, and grants aren't enough. dbt replaces a table model by
renaming the old table, and only the owner can rename it. This query prints the
statements that hand them over; run each one:

```sql
select 'alter schema ' || nspname || ' owner to "IAMR:orcavault-run-dbt-task-role";'
from pg_namespace
where nspname in ('psa', 'dcl', 'mart', 'seed', 'dbt_test__audit', 'ops')
union all
select 'alter table ' || schemaname || '.' || tablename || ' owner to "IAMR:orcavault-run-dbt-task-role";'
from pg_tables
where schemaname in ('psa', 'dcl', 'mart', 'seed', 'dbt_test__audit', 'ops')
  and tableowner <> 'IAMR:orcavault-run-dbt-task-role'
union all
select 'alter table ' || schemaname || '.' || viewname || ' owner to "IAMR:orcavault-run-dbt-task-role";'
from pg_views
where schemaname in ('psa', 'dcl', 'mart', 'seed', 'dbt_test__audit', 'ops')
  and viewowner <> 'IAMR:orcavault-run-dbt-task-role';
```

**Readers** get their own identities with read only. Default privileges make
tables the task creates later readable. Schema usage can only be granted once a
schema exists, so for new schemas that's after the first run:

```sql
alter default privileges for user "IAMR:orcavault-run-dbt-task-role"
    grant select on tables to "IAMR:<reader-role>";

grant usage on schema psa, dcl, mart, seed, dbt_test__audit, ops to "IAMR:<reader-role>";
grant select on all tables in schema psa, dcl, mart, seed, dbt_test__audit, ops to "IAMR:<reader-role>";
```

### 4. Subscribe to the alerts

```bash
aws sns subscribe --topic-arn "$(terraform output -raw alerts_topic_arn)" \
  --protocol email --notification-endpoint you@example.com
```

The no-success alarm is in ALARM until the first run succeeds.

### 5. Check the task, then run it

```bash
# Checks the task can get credentials and connect to Redshift.
eval "$(terraform output -raw debug_command)"

# A first full run, rather than waiting for the schedule.
eval "$(terraform output -raw start_run_command)"
```

## Operating

**Start a run** with `terraform output -raw start_run_command`, or from the Step
Functions console with input `{}`.

**Build part of the project** by passing `select`:

```bash
aws stepfunctions start-execution --state-machine-arn "$(terraform output -raw state_machine_arn)" \
  --input '{"select": "path:models/dcl/raw_vault/library+"}'
```

A partial build never moves the CDC positions, because not every model ran. The
next full run reads the same window again.

**Pass dbt vars** with `vars`, such as rereading the warehouse models from a
point in time:

```bash
--input '{"vars": {"reread_from": "2026-09-01"}}'
```

`load_legacy` reads the `data_portal` Glue database, which the task role has no
grants for. It is a one-off, so run it as an admin rather than through here.

**Pause the schedule** with `-var schedule_enabled=false`. This also turns off
the no-success alarm's notifications.

**Stop a run** by stopping its execution. Step Functions stops the task.

**Read the logs** with `terraform output -raw logs_command`, or from the link in
the alert.

**Release a new version** by building and pushing an image for the new ref,
then applying with the new `orcavault_release_ref`.

## Limits and risks

- **Query time limit.** The prod workgroup stops any query that runs longer
  than 900 seconds (`max_query_execution_time`). A large rebuild, such as the
  first full run or a reread from far back, can hit it. The run then fails, and
  the limit has to be raised for it.
- **Monthly compute limit.** The prod workgroup is deactivated once it uses 120
  RPU-hours in a month (`breach_action = "deactivate"`). Every run, and
  everything else on the workgroup, counts towards it. When it's reached, runs
  fail until the next month or until the limit is raised. Check the workgroup's
  usage after the first few runs.
- **Network.** The task runs in the private subnets of `UomPrimaryVpc`, without
  a public IP. It needs to reach ECR and CloudWatch Logs to start, the
  `redshift-serverless` API to get credentials, and the workgroup on port 5439.
  These need VPC endpoints or a NAT gateway. If any are missing the run fails,
  and `debug_command` is the quickest way to tell.
- **The old Aurora job** in `infra/ecs/legacy/orcavault-dbt` still runs daily until
  it's decommissioned.
