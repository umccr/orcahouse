# --- The run.
#
# One execution is one dbt build of the whole project, unless its input narrows
# it. dbt orders the models by their dependencies and builds independent ones in
# parallel, up to dbt_threads, so the state machine doesn't model the DAG.
#
# Input, all optional:
#
#   {"select": "<dbt selector>", "vars": {...}}
#
# select is passed to --select, and vars to --vars. The scheduled run passes
# neither.
#
# The execution fails if dbt exits non-zero, which is when any model, seed,
# snapshot or error-severity test fails. Models that did succeed stay loaded.

locals {
  run_timeout_seconds = var.run_timeout_hours * 3600
}

resource "aws_sfn_state_machine" "run" {
  name     = local.name_prefix
  role_arn = aws_iam_role.states.arn
  type     = "STANDARD"

  definition = jsonencode({
    Comment       = "Builds the OrcaVault dbt project on Redshift Serverless."
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
        Assign = {
          dbtSelect = "{% $exists($states.input.select) ? $string($states.input.select) : '' %}"
          dbtVars   = "{% $exists($states.input.vars) ? $string($states.input.vars) : '' %}"
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
        Type  = "Fail"
        Error = "RunInProgress"
        Cause = "Another OrcaVault dbt task is still running, so this run did not start."
      }

      # The .sync integration waits for the task to stop, and fails this state
      # if dbt exits non-zero. If the state times out, or the execution is
      # stopped, Step Functions stops the task.
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
                Name        = local.container_name
                Environment = "{% [$dbtSelect != '' ? {'Name': 'DBT_SELECT', 'Value': $dbtSelect}, $dbtVars != '' ? {'Name': 'DBT_VARS', 'Value': $dbtVars}] %}"
              }
            ]
          }
        }
        # Only failures to start the task are retried, such as throttling or no
        # Fargate capacity. A dbt failure is not retried: whatever failed would
        # most likely fail again, and the next daily run rereads the same window.
        Retry = [
          {
            ErrorEquals     = ["ECS.AmazonECSException", "AmazonECS.Unknown"]
            IntervalSeconds = 60
            MaxAttempts     = 3
            BackoffRate     = 2
          }
        ]
        End = true
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
