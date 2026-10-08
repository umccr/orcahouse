# --- The run.
#
# An execution runs one request, which is its input, see the README. The
# scheduled run's input is {}, which builds the whole project. dbt orders the
# models by their dependencies and builds independent ones in parallel, up to
# dbt_threads, so the state machine doesn't model the DAG.
#
# The runner in the image checks the request, runs it, and writes how it went
# to the results bucket, at runs/<execution name>/event.json. Whatever happens,
# the execution then sends one "OrcaVault Run Finished" event to the default
# event bus with the run's outcome. It succeeds when the outcome is succeeded or
# warned, and otherwise fails with the outcome as its error.

locals {
  run_timeout_seconds = var.run_timeout_hours * 3600

  # The event's detail, for when the runner didn't get to write one.
  empty_event_detail = {
    environment       = var.environment
    modelsSucceeded   = 0
    modelsFailed      = 0
    modelsSkipped     = 0
    testsPassed       = 0
    testsWarned       = 0
    testsFailed       = 0
    failedNodes       = ""
    warnedNodes       = ""
    positionsAdvanced = null
    orcavaultRef      = var.orcavault_release_ref
    logsUrl           = null
  }

  # Each reason the runner might not write the event, which is then its error.
  # Like the runner's errors, these are one line without double quotes, so that
  # EventBridge input transformers can use them.
  no_runner_events = {
    run_in_progress = {
      outcome = "skipped"
      error   = "Another OrcaVault dbt task was still running, so this run didn't start"
    }
    check_failed = {
      outcome = "error"
      error   = "Couldn't check for another run in progress, so this run didn't start. The execution has the details"
    }
    no_event = {
      outcome = "error"
      error   = "The runner wrote no event. Its task may have failed to start, or been killed. The execution has the details"
    }
  }

  no_runner_event_detail = {
    for name, event in local.no_runner_events : name => join("", [
      "{% $merge([",
      jsonencode(merge(local.empty_event_detail, event)),
      ", {'runId': $states.context.Execution.Name, ",
      "'durationMinutes': $round(($millis() - $toMillis($states.context.Execution.StartTime)) / 60000)}]) %}",
    ])
  }
}

resource "aws_sfn_state_machine" "run" {
  name     = local.name_prefix
  role_arn = aws_iam_role.states.arn
  type     = "STANDARD"

  definition = jsonencode({
    Comment       = "Runs the OrcaVault dbt project on Redshift Serverless."
    QueryLanguage = "JSONata"
    StartAt       = "CheckNoRunInProgress"

    States = {
      # Overlapping runs are not safe for OrcaVault's incremental models, and a
      # run can be started by hand as well as by the schedule. This catches a
      # run started any way, including with ecs run-task.
      CheckNoRunInProgress = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:ecs:listTasks"
        Arguments = {
          Cluster       = aws_ecs_cluster.this.arn
          Family        = aws_ecs_task_definition.dbt.family
          DesiredStatus = "RUNNING"
        }
        Output = "{% { 'running': $count($states.result.TaskArns) } %}"
        Retry = [
          {
            ErrorEquals     = ["States.ALL"]
            IntervalSeconds = 10
            MaxAttempts     = 3
            BackoffRate     = 2
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Assign      = { detail = local.no_runner_event_detail["check_failed"] }
            Next        = "SendEvent"
          }
        ]
        Next = "IsRunInProgress"
      }

      IsRunInProgress = {
        Type = "Choice"
        Choices = [
          {
            Condition = "{% $states.input.running > 0 %}"
            Next      = "RunInProgress"
          }
        ]
        Default = "RunDbt"
      }

      RunInProgress = {
        Type    = "Pass"
        Comment = "Another OrcaVault dbt task is still running, so this run doesn't start."
        Assign  = { detail = local.no_runner_event_detail["run_in_progress"] }
        Next    = "SendEvent"
      }

      # The .sync integration waits for the task to stop, and fails this state
      # if the runner exits non-zero, which it does for any outcome but
      # succeeded or warned. Either way, the runner has written the event. If
      # the state times out, or the execution is stopped, Step Functions stops
      # the task.
      #
      # The execution name is the run ID, which names the run's event.
      RunDbt = {
        Type           = "Task"
        Resource       = "arn:aws:states:::ecs:runTask.sync"
        TimeoutSeconds = local.run_timeout_seconds
        Arguments = {
          Cluster        = aws_ecs_cluster.this.arn
          TaskDefinition = aws_ecs_task_definition.dbt.arn
          LaunchType     = "FARGATE"
          NetworkConfiguration = {
            AwsvpcConfiguration = {
              Subnets        = data.aws_subnets.uom_private_subnets_ids.ids
              SecurityGroups = [data.aws_security_group.uom_primary_sg.id]
              AssignPublicIp = "DISABLED"
            }
          }
          Overrides = {
            ContainerOverrides = [
              {
                Name = local.container_name
                Environment = [
                  { Name = "ORCAVAULT_RUN_ID", Value = "{% $states.context.Execution.Name %}" },
                  { Name = "ORCAVAULT_RUN_REQUEST", Value = "{% $string($states.context.Execution.Input) %}" },
                ]
              }
            ]
          }
        }
        # Only failures to start the task are retried, such as throttling or no
        # Fargate capacity. A failed run is not: whatever failed would most
        # likely fail again, and the next daily run rereads the same window.
        # Run it again by hand once the cause is fixed, see the README.
        Retry = [
          {
            ErrorEquals     = ["ECS.AmazonECSException", "AmazonECS.Unknown"]
            IntervalSeconds = 60
            MaxAttempts     = 3
            BackoffRate     = 2
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "ReadEvent"
          }
        ]
        Next = "ReadEvent"
      }

      ReadEvent = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:s3:getObject"
        Arguments = {
          Bucket = aws_s3_bucket.results.bucket
          Key    = "{% '${local.results_prefix}' & $states.context.Execution.Name & '/event.json' %}"
        }
        Assign = { detail = "{% $parse($states.result.Body) %}" }
        Output = {}
        Retry = [
          # A timed out task is stopped without waiting for it, and the runner
          # can take up to the container's stopTimeout to write its event.
          {
            ErrorEquals     = ["S3.NoSuchKeyException"]
            IntervalSeconds = 30
            MaxAttempts     = 5
            BackoffRate     = 1
          },
          {
            ErrorEquals     = ["States.ALL"]
            IntervalSeconds = 5
            MaxAttempts     = 3
            BackoffRate     = 2
          },
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Assign      = { detail = local.no_runner_event_detail["no_event"] }
            Next        = "SendEvent"
          }
        ]
        Next = "SendEvent"
      }

      SendEvent = {
        Type     = "Task"
        Resource = "arn:aws:states:::events:putEvents"
        Arguments = {
          Entries = [
            {
              EventBusName = "default"
              Source       = local.event_source
              DetailType   = local.event_detail_type
              Detail       = "{% $merge([$detail, {'executionUrl': '${local.execution_url_prefix}' & $states.context.Execution.Id}]) %}"
            }
          ]
        }
        Output = {}
        Retry = [
          {
            ErrorEquals     = ["States.ALL"]
            IntervalSeconds = 10
            MaxAttempts     = 3
            BackoffRate     = 2
          }
        ]
        # The execution still ends with the run's outcome, so that the
        # execution status alert in monitoring.tf sees a failed run.
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "Finish"
          }
        ]
        Next = "Finish"
      }

      Finish = {
        Type = "Choice"
        Choices = [
          {
            Condition = "{% $detail.outcome in ['succeeded', 'warned'] %}"
            Next      = "Succeeded"
          }
        ]
        Default = "Failed"
      }

      Succeeded = {
        Type   = "Succeed"
        Output = "{% $detail %}"
      }

      Failed = {
        Type  = "Fail"
        Error = "{% $detail.outcome %}"
        Cause = "{% $detail.error ? $detail.error : 'The run ended with ' & $detail.outcome & ': ' & $detail.failedNodes %}"
      }
    }
  })
}

# --- The daily schedule.

resource "aws_scheduler_schedule" "daily" {
  name       = "${local.name_prefix}-daily"
  group_name = "default"
  state      = var.schedule_enabled ? "ENABLED" : "DISABLED"

  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = var.schedule_timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_sfn_state_machine.run.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({})

    # Retries starting the execution, not the run itself.
    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 5
    }
  }
}
