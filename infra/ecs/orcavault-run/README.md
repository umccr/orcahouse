# OrcaVault daily run

Builds the [umccr/orcavault](https://github.com/umccr/orcavault) dbt project on
Redshift Serverless once a day, in dev and in prod.

```
EventBridge Scheduler, 03:00 Australia/Melbourne, input {}
  └─ Step Functions state machine orcavault-run-<env>
       1. CheckNoRunInProgress   skips the run if the environment's dbt task is already running
       2. RunDbt                 ECS Fargate task running the request, and waits for it
                                   └─ writes to S3 orcavault-run-<env>-results-…/runs/<execution name>/event.json
       3. ReadEvent              reads the event the task wrote
       4. AddRunFields           adds the fields every run's event has, such as runId
       5. SendEvent              sends "OrcaVault Run Finished" to the default event bus
       6. Finish                 succeeds if the run succeeded or only warned
  └─ CloudWatch alarm orcavault-run-<env>-no-recent-success
       - no run has succeeded in the last 30 hours
```

This replaces `infra/ecs/legacy/orcavault-dbt`, which runs the retired
`orcahouse/orcavault` project against Aurora. That stack still has its own
daily schedule, and decommissioning it is a separate change.

## Environments

Dev and prod each have their own run, which builds the orcavault database in
their own workgroup, `orcahouse-dev` or `orcahouse-prod`. Both are in the
warehouse account, so everything an environment creates is named after it,
such as `orcavault-run-dev`, and neither touches the other's runs.

| Directory                                | What it has                                                         | Applied         |
|------------------------------------------|---------------------------------------------------------------------|-----------------|
| `account-wide`                           | The image repository, `orcavault-run-dbt`                           | once            |
| `environments/dev`, `environments/prod`  | The run: schedule, state machine, task, roles, results and alarm    | per environment |
| `modules/orcavault-run`                  | What each environment applies                                       |                 |

- **One image for both.** An image is built once for an orcavault ref, and dev
  runs it first. A release reaches prod by setting prod to the same ref, so
  prod runs the very image dev ran, rather than a rebuild that could resolve
  different dependencies.
- **The same CDC.** Both read the OrcaBus CDC from the prod landing zone and
  the `orcabus_*` Glue databases, since only prod has DMS. Each writes only to
  its own workgroup.
- **Each workgroup's own `tsa`.** OrcaVault also reads the `tsa` schema in its
  own database, so OrcaGlue has to load it in dev as well as prod. Without it,
  dev's `tsa` models fail, and so does everything downstream of them.

## Why this design

- **dbt orders the work itself.** A run is one dbt command, `dbt build` by
  default, and dbt knows every model's dependencies, so the state machine
  doesn't need to model them. A state machine with one step per model would
  duplicate the DAG and drift from it.
- **ECS Fargate runs dbt.** A run can take longer than Lambda's 15 minutes, and
  a container pins the dbt version and project code in an image.
- **Step Functions runs the task.** It keeps a history of every run, stops the
  task at a timeout, checks that no other run is going, and emits an event when
  a run fails. Scheduling the task straight from EventBridge, as the old Aurora
  job does, gives none of the first three.
- **A small runner wraps dbt.** It checks the request before dbt starts, and
  sums the run up as an event, with what failed and why. The state machine
  can't do that, because it only sees the task's exit code. It's in
  `docker/runner`.
- **One event per run.** Every execution ends by sending one event with the
  run's outcome, whether it succeeded, failed, was skipped or never started.
  Notifications are built on it rather than on the state machine's own status
  events, which can't tell a failed test from a failed model.
- **No Airflow.** MWAA would also work, but it is an always-on environment for
  what is a single daily job.

## What a run does

### Order and parallelism

dbt builds the models in dependency order, and up to `dbt_threads` independent
models at once (4 by default). More threads than the workgroup's RPU can serve
only queue in Redshift, so raise them together.

`dbt build` runs each model's tests straight after the model. A failing
error-severity test skips everything downstream of that model, so bad data
doesn't spread. Warn-severity tests only log. The unit tests are left out by
default, because they test the project code against fixtures, which is a job
for CI.

### Outcomes

Each run ends with one of these, which is the `outcome` of its event:

| Outcome         | Meaning                                                                   | Execution |
|-----------------|---------------------------------------------------------------------------|-----------|
| `succeeded`     | Everything built and every test passed.                                   | succeeds  |
| `warned`        | Only warn-severity tests failed. Nothing was held back.                   | succeeds  |
| `failed`        | A model didn't build, or an error-severity test or a hook failed.         | fails     |
| `error`         | dbt couldn't run, the request was invalid or selected nothing, or the run was stopped or never started. | fails |
| `skipped`       | Another run was still going, so this one didn't start.                    | fails     |

A failed execution's error is the outcome, and its cause is the event's
`error`, or else the failed nodes, so the Step Functions console shows what
happened.

### When some models fail

The run is reported as failed, and everything that could load does load.

- Models that succeeded stay loaded. Each model commits on its own.
- A failed model skips only the models that depend on it. Unrelated models
  still build, unless the run was started with `--fail-fast`.
- The CDC positions in `ops.cdc_watermark` only move when every model in the
  project succeeds in one `dbt run` or `dbt build`. After a partial failure
  they stay put, and the next run rereads the same window. The models skip rows
  they already have, so the rereading is harmless, and the next successful run
  catches up by itself. See
  [docs/watermark-architecture.md](https://github.com/umccr/orcavault/blob/main/docs/watermark-architecture.md).

The trade-off is that one model that keeps failing holds every position back,
so each run rereads a bigger window until it's fixed. Fix failures within days,
not weeks.

A failed run is not retried automatically. Whatever failed would most likely
fail again, and the next daily run covers it. Once the cause is fixed, run it
again by hand, see [Running again after a failure](#running-again-after-a-failure).
Only failures to start the task, such as no Fargate capacity, are retried
automatically.

### Overlapping runs

OrcaVault's incremental models assume runs don't overlap. Two things prevent it:

- `CheckNoRunInProgress` skips the run if the environment's OrcaVault dbt task
  is already running, however it was started. The execution fails with
  `skipped`. Dev and prod don't hold each other up, as they build different
  workgroups.
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

Create the image repository once, then set up each environment, dev first.
The commands are run from this directory:

```bash
export AWS_PROFILE=unimelb-warehouse-prod-admin
```

### 1. Create the image repository

```bash
terraform -chdir=account-wide init
terraform -chdir=account-wide apply
```

### 2. Build and push the image

`orcavault_release_ref` is the orcavault tag or commit the image is built from,
and its ECR tag. Each environment sets it in its `release.auto.tfvars`. Tags
are immutable. Pin a release tag or commit, never a branch, so that the code
behind any load can be found again.

```bash
REF=$(sed -n 's/^orcavault_release_ref *= *"\(.*\)"$/\1/p' environments/dev/release.auto.tfvars)
REPO=$(terraform -chdir=account-wide output -raw ecr_repository_url)
aws ecr get-login-password | docker login --username AWS --password-stdin "${REPO%%/*}"
docker buildx build --platform linux/arm64 --build-arg "ORCAVAULT_REF=$REF" -t "$REPO:$REF" --push docker/
```

The image holds orcavault at that ref with the dbt version it pins, and the
runner from `docker/runner` with the versions in its `uv.lock`, each in an
environment of its own. The build runs `dbt parse`, so a project that doesn't
parse fails here rather than at 3am. Both environments run the same image, so
push each ref once.

### 3. Apply the environment

```bash
ENV=dev
terraform -chdir=environments/$ENV init
terraform -chdir=environments/$ENV apply
```

The applying role must be a Lake Formation admin, because
`modules/orcavault-run/lakeformation.tf` grants the task role read on the CDC
Glue databases.

### 4. Grant the task's database user

dbt connects with Redshift IAM auth as the task role, so its database user is
`IAMR:orcavault-run-<env>-dbt-task-role`
(`terraform -chdir=environments/$ENV output -json orcavault_run | jq -r .dbt_task_db_identity`). It
creates and owns everything OrcaVault writes: the `psa`, `dcl`, `mart`, `seed`,
`dbt_test__audit` and `ops` schemas.

As a Redshift admin, in the environment's workgroup, before its first run, with
`<env>` replaced by `dev` or `prod`:

```sql
-- Created on first connection anyway, but the grants need it to exist.
create user "IAMR:orcavault-run-<env>-dbt-task-role" password disable;

-- dbt creates its schemas when they're missing.
grant create on database orcavault to "IAMR:orcavault-run-<env>-dbt-task-role";

-- The CDC sources.
grant usage on database awsdatacatalog to "IAMR:orcavault-run-<env>-dbt-task-role";

-- tsa is written by OrcaGlue and read by OrcaVault.
grant usage on schema tsa to "IAMR:orcavault-run-<env>-dbt-task-role";
grant select on all tables in schema tsa to "IAMR:orcavault-run-<env>-dbt-task-role";
-- Only needed if OrcaGlue creates new tsa tables rather than reloading them.
alter default privileges for user "<orcaglue-user>" in schema tsa
    grant select on tables to "IAMR:orcavault-run-<env>-dbt-task-role";
```

**If OrcaVault has already been built here as another user**, that user owns
its schemas and tables, and grants aren't enough. dbt replaces a table model by
renaming the old table, and only the owner can rename it. This query prints the
statements that hand them over; run each one:

```sql
select 'alter schema ' || nspname || ' owner to "IAMR:orcavault-run-<env>-dbt-task-role";'
from pg_namespace
where nspname in ('psa', 'dcl', 'mart', 'seed', 'dbt_test__audit', 'ops')
union all
select 'alter table ' || schemaname || '.' || tablename || ' owner to "IAMR:orcavault-run-<env>-dbt-task-role";'
from pg_tables
where schemaname in ('psa', 'dcl', 'mart', 'seed', 'dbt_test__audit', 'ops')
  and tableowner <> 'IAMR:orcavault-run-<env>-dbt-task-role'
union all
select 'alter table ' || schemaname || '.' || viewname || ' owner to "IAMR:orcavault-run-<env>-dbt-task-role";'
from pg_views
where schemaname in ('psa', 'dcl', 'mart', 'seed', 'dbt_test__audit', 'ops')
  and viewowner <> 'IAMR:orcavault-run-<env>-dbt-task-role';
```

**Readers** get their own identities with read only. Default privileges make
tables the task creates later readable. Schema usage can only be granted once a
schema exists, so for new schemas that's after the first run:

```sql
alter default privileges for user "IAMR:orcavault-run-<env>-dbt-task-role"
    grant select on tables to "IAMR:<reader-role>";

grant usage on schema psa, dcl, mart, seed, dbt_test__audit, ops to "IAMR:<reader-role>";
grant select on all tables in schema psa, dcl, mart, seed, dbt_test__audit, ops to "IAMR:<reader-role>";
```

### 5. Check the task, then run it

The task needs the network access listed under
[Limits and risks](#limits-and-risks).

```bash
# Checks the task can get credentials and connect to Redshift.
eval "$(terraform -chdir=environments/$ENV output -json orcavault_run | jq -r .debug_command)"

# A first full run, rather than waiting for the schedule.
eval "$(terraform -chdir=environments/$ENV output -json orcavault_run | jq -r .start_run_command)"
```

## Operating

Each environment is run on its own. The `terraform` commands here are run in
its directory, `environments/dev` or `environments/prod`. Its outputs are under
`orcavault_run`, so read one with `terraform output -json orcavault_run | jq -r .<name>`.

**Start a run** with the `start_run_command` output, or from the Step
Functions console with input `{}`. Leave the execution name to Step Functions,
or use only letters, digits, `-` and `_`: the name is the run's ID, and names
its event.

**Pause the schedule** with `-var schedule_enabled=false`.

**Stop a run** by stopping its execution. Step Functions stops the task, and
the runner tells dbt to cancel its queries. If dbt hasn't exited after two
minutes, ECS kills the task, and the state machine sends the run's event
instead. A run that reaches `run_timeout_hours` is stopped the same way.

**Read the logs** with the `logs_command` output, or from the
`logsUrl` in the run's event.

**Release a new version** by setting the new ref as `orcavault_release_ref` in
`environments/dev/release.auto.tfvars`, building and pushing its image, and
applying dev. Once dev's runs have gone well, set prod's to the same ref and
apply prod. Commit each change, so that the files say what each environment
runs.

### Requests

The execution input is the dbt arguments for the run. The scheduled run's `{}`
is `dbt build`, of everything. Anything else gives the arguments:

```json
{"args": ["build", "--select", "path:models/dcl/raw_vault/library+", "--vars", "{\"reread_from\": \"2026-09-01\"}"]}
```

`args` can also be a string, split as a shell would, such as
`{"args": "build --select +lims --full-refresh"}`. orcavault names the common
parts of the project in its `selectors.yml`, such as
`{"args": "build --selector orcabus"}` for everything built from the OrcaBus
CDC.

- **The command is `build`, `run`, `test`, `seed` or `snapshot`**, the ones
  that build or test. Others, such as `ls`, can be run through the image, see
  [Running the image by hand](#running-the-image-by-hand). `run-operation`
  isn't allowed, because it runs any macro with the task's grants.
- **The image sets two dbt defaults**, which the arguments can override. Unit
  tests are left out (`DBT_EXCLUDE_RESOURCE_TYPES`). A `--select` or
  `--exclude` that matches nothing is an error (`DBT_WARN_ERROR_OPTIONS`), so
  a misspelt model fails the run, rather than the run succeeding having done
  nothing.
- **The target is `ecs`**, the only one in the image's profile, in every
  environment. The task's environment decides which workgroup it builds.
- **A request is checked before dbt starts.** One that isn't one of these
  shapes, or names another command, ends the run with `error` straight away.
  So does a misspelt flag, which dbt rejects before it connects.

**A run is one dbt command.** To run several in order, such as a full refresh
of one model and then a normal build, start each execution once the last has
finished, and only if it succeeded. One started while another is going is
skipped, not run alongside it.

Things to know:

- **A partial run never moves the CDC positions**, because not every model ran.
  The next full run reads the same window again.
- **`run` skips the tests.** A full `{"args": ["run"]}` does move the
  positions, without tests having checked what it loaded. Prefer `build`, and
  to leave the tests out, `--exclude resource_type:test`.
- **`--full-refresh` rebuilds incremental models from scratch**, which for the
  raw vault means rereading every CDC file. It can hit the query time limit,
  see [Limits and risks](#limits-and-risks).
- **`load_legacy`** reads the `data_portal` Glue database, which the task role
  has no grants for. It's a one-off, so run it as an admin rather than through
  here.

### Running again after a failure

Once the cause is fixed, start the same request again, which for a scheduled
run is `{}`. dbt builds everything again, and the models skip the rows they
already have, so nothing is loaded twice. Only a full run moves the CDC
positions, so it's also what catches the project up.

To rebuild only part, such as the model that failed and what depends on it,
select it: `{"args": "build --select lims+"}`. That doesn't move the CDC
positions, so follow it with a full run, or leave that to the schedule.

Run again with a new execution rather than a
[redrive](https://docs.aws.amazon.com/step-functions/latest/dg/redrive-executions.html).
A redriven failed execution only fails again, since it ended in a Fail state.
A redriven stopped one runs the whole request again, under the same name.

### The run's event

Every execution ends by sending this event to the default event bus, whatever
happened. Notifications, and anything else that reacts to a run, should use it.

The runner writes how the run went, from `outcome` to `warnedNodes`, to
`runs/<execution name>/event.json` in the results bucket
(the `results_bucket` output). It's kept for
`results_retention_days` (90 by default). The state machine reads it, adds the
fields every run's event has, `environment`, `runId`, `orcavaultRef`,
`durationMinutes`, `logsUrl` and `executionUrl`, and sends it. When the runner
didn't write one, because the run was skipped or the task didn't start or was
killed, the state machine sends one with counts of 0 and says why in `error`.

```json
{
  "source": "orcahouse.orcavault",
  "detail-type": "OrcaVault Run Finished",
  "detail": {
    "environment": "prod",
    "outcome": "failed",
    "error": null,
    "runId": "4b8e1f3a-…",
    "modelsSucceeded": 140,
    "modelsFailed": 0,
    "modelsSkipped": 3,
    "testsPassed": 512,
    "testsWarned": 1,
    "testsFailed": 1,
    "failedNodes": "unique_hub_library_library_hk",
    "warnedNodes": "accepted_values_lims_type",
    "orcavaultRef": "v1.2.3",
    "durationMinutes": 42,
    "logsUrl": "https://ap-southeast-2.console.aws.amazon.com/cloudwatch/home?…",
    "executionUrl": "https://ap-southeast-2.console.aws.amazon.com/states/home?…"
  }
}
```

- The detail is flat, and every field is always there, so that an EventBridge
  input transformer can use it as it is.
- `environment` is `dev` or `prod`. Both send to the same event bus with the
  same source and detail type, so a rule for one environment matches on it.
- `error` says why the outcome is `error` or `skipped`, such as
  `The run was stopped`, and is null otherwise. It's one line of at most 300
  characters, without double quotes or backslashes, so that an input
  transformer can put it in a JSON string. It's never dbt's own message, which
  can quote data. The logs have that.
- `failedNodes` and `warnedNodes` name at most 10 nodes, then "and N more". The
  logs have the full lists.
- `durationMinutes` is from when the execution started.
- `logsUrl` is the task's log stream. It's null when the task never started,
  and when the run timed out, since Step Functions doesn't then say which task
  it was. The execution has it, under RunDbt.

### Running the image by hand

With arguments, the image runs them as a dbt command and records nothing, which
is what `debug_command` does. Without, it runs the request in
`ORCAVAULT_RUN_REQUEST`. For example, locally, with AWS credentials that can
connect to Redshift:

```bash
docker run --rm -e AWS_PROFILE -v ~/.aws:/home/dbt/.aws:ro \
  -e ORCAVAULT_REDSHIFT_HOST=<workgroup endpoint> \
  -e ORCAVAULT_RUN_REQUEST='{"args": "test --select mart"}' \
  "$REPO:$REF"
```

Without `ORCAVAULT_RESULTS_BUCKET`, the event stays in the container, under
`ORCAVAULT_RESULTS_DIR`. See `docker/runner/orcavault_runner/__main__.py` for
the rest of the environment.

The runner's tests don't need dbt or AWS, only
[uv](https://docs.astral.sh/uv/getting-started/installation/):

```bash
cd docker/runner
uv run pytest
```

Its code is linted and formatted with ruff, which CI checks:

```bash
uv run ruff check --fix
uv run ruff format
```

Its dependencies are in `docker/runner/pyproject.toml`. After changing them, run
`uv lock`, and commit `uv.lock`, which is what the image installs. dbt isn't one
of them: the image has the version orcavault pins.

The Terraform tests are the module's, and don't need AWS either:

```bash
cd modules/orcavault-run
terraform init -backend=false
terraform test
```

## Limits and risks

- **Query time limit.** Each workgroup stops any query that runs longer than
  900 seconds (`max_query_execution_time`). A large rebuild, such as the first
  full run or a reread from far back, can hit it. The run then fails, and the
  limit has to be raised for it.
- **Monthly compute limit.** Each workgroup is deactivated once it uses 120
  RPU-hours in a month (`breach_action = "deactivate"`). Every run, and
  everything else on the workgroup, counts towards it, so dev's daily runs
  count towards dev's. When it's reached, runs fail until the next month or
  until the limit is raised. Check the workgroup's usage after the first few
  runs.
- **Image archiving.** An image that no environment has pulled for 90 days is
  archived, and deleted a year later, see `account-wide/main.tf`. An
  environment paused for that long needs its image restored, or a new one,
  before it runs again.
- **Network.** The task runs in the private subnets of `UomPrimaryVpc`, without
  a public IP. It needs to reach ECR and CloudWatch Logs to start, the
  `redshift-serverless` API to get credentials, the workgroup on port 5439, and
  S3 to write its event. These need VPC endpoints or a NAT gateway. ECR
  already needs S3 for image layers, but if the S3 endpoint has a policy, it
  must allow the results bucket too. If any are missing the run fails, and
  `debug_command` is the quickest way to tell. Without S3, a run ends with
  `error`, saying the runner wrote no event, even when dbt succeeded.
- **The old Aurora job** in `infra/ecs/legacy/orcavault-dbt` still runs daily until
  it's decommissioned.
