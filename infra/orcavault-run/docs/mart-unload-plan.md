# Plan: automate the mart UNLOAD and the Aurora reload

The mart is unloaded from Redshift, and loaded into the OrcaNexus Aurora
database by OrcaGlue's `spreadsheet-mart-tables` job, by hand. This plan makes
the OrcaVault run unload it after each build, and its run event start the job.
How they work is in [The unload][unload] and OrcaGlue's [Trigger][trigger].

## Decisions

| Question          | Decision                                                                                    |
| ----------------- | ------------------------------------------------------------------------------------------- |
| Where it runs     | A third state machine step, `unload`, after `crawl` and `dbt`, in its own dbt task          |
| When              | Only after a `dbt` step that `succeeded` or `warned`                                        |
| Manual runs       | `unload` is a default step. `"steps": ["crawl", "dbt"]` leaves it out                       |
| The procedure     | The PowerUser owns it, and deploys it by hand when it changes. The run only calls it        |
| Who can call it   | Its owner, superusers and `orcavault_builder`, which each deploy grants `EXECUTE`           |
| The success event | `OrcaVaultRunFinished` gets `unloadOutcome`                                                 |
| The subscription  | In OrcaGlue's `spreadsheet-mart-tables` stack, replacing the job's schedule                 |
| New mart tables   | Reach Aurora only once they're in OrcaGlue's `job/mart_tables.json` and the OrcaNexus model |

## Design

```text
Scheduler, 03:00 Melbourne time, {}
  ▼
orcavault-run-<env>       crawl → dbt build → unload → OrcaVaultRunFinished
                                                │              │ outcome succeeded or warned,
                                                ▼              │ unloadOutcome succeeded
s3://orcavault-<env>-warehouse-…/v1/            ▼
  csv/mart/<table>/       ◄── read by ── orcaglue-<env>-spreadsheet-mart-tables-start (rule)
  parquet/mart/<table>/   ◄── mart crawler, on its own schedule     ▼
                                                orcaglue-<env>-spreadsheet-mart-tables-workflow
                                                  ▼ EVENT trigger
                                                orcaglue-<env>-spreadsheet-mart-tables-job
                                                  ▼
                                                Aurora orcanexus-<env>, mart
```

`ShouldUnload` follows `ReadEvent`, and `RunUnload` runs the dbt task with
`ORCAVAULT_RUN_STEP=unload`. `AddUnloadOutcome` merges its
`runs/<execution name>/unload/event.json` into the run's detail. A failed unload
fails the execution, so the existing Slack rules report it:

| dbt step                     | unload step                     | `outcome`                          | `unloadOutcome` |
| ---------------------------- | ------------------------------- | ---------------------------------- | --------------- |
| `succeeded`, `warned`        | succeeded                       | unchanged                          | `succeeded`     |
| `succeeded`, `warned`        | the call failed                 | `failed`, with `run_unload_schema` | `failed`        |
| `succeeded`, `warned`        | couldn't run, stopped, no event | `error`, with why                  | `failed`        |
| `failed`, `error`, `skipped` | not started                     | unchanged                          | `not_run`       |
| not a step                   | ran                             | the unload's                       | the unload's    |

### The orcavault fix

As merged, the procedure's schema check reads `information_schema.schemata`,
which in Redshift only lists the caller's own schemas, so the task's user gets
`Schema "mart" does not exist`. Also, only its owner and superusers can call it.
The fix checks `pg_namespace` instead, and each deploy grants `EXECUTE` to
`orcavault_builder`, the role both task users have. The procedure runs with the
caller's permissions, so the grant gives no new access.

## Changes

| Repository | Branch                                       | Change                                                                       |
| ---------- | -------------------------------------------- | ---------------------------------------------------------------------------- |
| orcavault  | `fix/unload-schema-procedure`                | `deploy_unload_schema.sql`, as above, and the README                         |
| orcahouse  | `feat/orcavault-run-unload`                  | The runner's unload step, the module's `unload` and its states, and the docs |
| orcaglue   | `feat/spreadsheet-mart-tables-event-trigger` | The workflow, event trigger, rule and role, in place of the schedule         |

No IAM change is needed in orcahouse, as Redshift unloads with its namespace
role.

## Rollout

Dev is deployed from the branches, to test before the review. Prod waits until
the team has approved the pull requests.

### Phase 1: dev, from the branches

1. Push the orcavault branch and open its pull request. Its head commit is the
   dev ref.
2. As the PowerUser, deploy the procedure in dev from the branch, see [the
   initial load][initial-load].
3. Set the dev `release.auto.tfvars` to that ref, build and push the image from
   the orcahouse branch, and apply dev, see [Releasing a version][release]. Tags
   are immutable, so if only the runner changes, delete the dev tag before
   pushing again, never a tag prod uses:

   ```bash
   aws ecr batch-delete-image --repository-name orcavault-run-dbt --image-ids imageTag="$REF"
   ```

4. Run the `start_unload_command` output. Check that `unloadOutcome` is
   `succeeded`, and that the manifests are new, see
   [Verification](#verification).
5. Check that the next scheduled dev run builds and unloads.
6. Delete the disabled Query Editor v2 scheduled query `QS2-UNLOAD-mart-dev`:

   ```bash
   RULE=QS2-UNLOAD-mart-dev
   aws events remove-targets --rule "$RULE" --ids $(aws events list-targets-by-rule --rule "$RULE" --query 'Targets[].Id' --output text)
   aws events delete-rule --name "$RULE"
   ```

7. Deploy the orcaglue dev stack with `trigger-enabled: "true"`, and commit it
   to the orcaglue pull request. Check that the next dev run starts the
   workflow.

### Gate: the team approves the pull requests

Merge the orcavault pull request. Then set both environments'
`release.auto.tfvars` to its merge commit in the orcahouse pull request, and
merge it and the orcaglue one. Prod runs `d9af3f2`, which has no
`run_unload_schema`, so the bump goes in the same pull request as prod's unload.
The release also brings #53 (per-source CDC watermarks) and #56 (the
`accreditation_lims` and `external_lims` marts).

### Phase 2: prod

8. Deploy the procedure in prod from the orcavault merge commit, as in step 2,
   before step 9. Redeploy dev too if it changed during the review.
9. Build the merge commit's image from orcahouse main, and apply dev and then
   prod.
10. Do steps 4 and 5 in prod.
11. Do step 6 with `RULE=QS2-UNLOAD-mart-prod`.
12. Do step 7 in prod, with a follow-up orcaglue pull request.

### Phase 3: clean up

13. Stop unloading and starting the job by hand.

## Verification

```bash
# The manifests of the last unload.
aws s3 ls s3://orcavault-dev-warehouse-115253169271-ap-southeast-2-an/v1/csv/mart/ --recursive | grep _manifest

# Start the dev job without a run, with an event that no Slack rule matches.
aws events put-events --entries '[{"EventBusName": "default", "Source": "orcahouse.orcavault", "DetailType": "OrcaVaultRunFinished", "Detail": "{\"environment\": \"dev\", \"outcome\": \"succeeded\", \"unloadOutcome\": \"succeeded\", \"crawlIncomplete\": \"\"}"}]'
aws glue get-workflow-runs --name orcaglue-dev-spreadsheet-mart-tables-workflow --max-results 1
```

## Rollback

| What             | How                                                                                         |
| ---------------- | ------------------------------------------------------------------------------------------- |
| The unload step  | Set the environment's `unload` to `null` and apply, or run with `"steps": ["crawl", "dbt"]` |
| The Glue trigger | `trigger-enabled: "false"` and `pulumi up`. Aurora keeps its tables                         |
| The procedure    | Its owner deploys an earlier ref, after taking the unload step out                          |

## Risks

- **A forgotten deploy.** A change to the procedure only takes effect once its
  owner redeploys it, so until then the run calls the old one.
- **Cost.** A second Fargate task start per run, about a minute, and about 20
  seconds of UNLOADs.
- **Overlapping and manual runs**, see [Other considerations][other] and
  OrcaGlue's [Trigger][trigger].

## Follow-ups

- An alarm for when the job hasn't loaded Aurora for a day.
- Start the mart crawler from the same event, rather than its schedule.
- Load `accreditation_lims` and `external_lims` into Aurora.
- Quote the procedure's UNLOAD strings, if it's ever needed.

[unload]: ../README.md#the-unload
[release]: ../README.md#releasing-a-version
[other]: ../README.md#other-considerations
[initial-load]: initial-load.md#4-grant-the-tasks-database-user
[trigger]:
  https://github.com/umccr/orcaglue/tree/main/spreadsheet-mart-tables#trigger
