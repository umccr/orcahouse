# The Step Functions run definition for the orcavault runner.

locals {
  run_timeout_seconds = var.run_timeout_hours * 3600

  # Warning is a successful outcome because models were still applied correctly.
  outcomes           = ["succeeded", "warned", "failed", "error", "skipped"]
  succeeded_outcomes = ["succeeded", "warned"]

  # The event detail used if the runner didn't write one.
  empty_event_detail = {
    modelsSucceeded = 0
    modelsFailed    = 0
    modelsSkipped   = 0
    testsPassed     = 0
    testsWarned     = 0
    testsFailed     = 0
    failedNodes     = ""
    warnedNodes     = ""
  }

  # Map the reasons for why the runner might not have written the event, which then defines the error message.
  no_runner_events = {
    run_in_progress = {
      outcome = "skipped"
      error   = "Another OrcaVault dbt task was still running, so this run didn't start"
    }
    check_failed = {
      outcome = "error"
      error   = "Couldn't check for another run, so this run didn't start. Check the execution for details"
    }
    no_event = {
      outcome = "error"
      error   = "The runner wrote no event. The task may have failed to start, or been killed. Check the execution for details"
    }
  }

  no_runner_event_detail = {
    for name, event in local.no_runner_events : name => merge(local.empty_event_detail, event)
  }
}

# Adds the fields every stage's event has, sends the event and finishes with the outcome.
module "finish" {
  source = "../sfn-finish"

  environment        = var.environment
  event_source       = local.event_source
  event_detail_type  = local.event_detail_type
  succeeded_outcomes = local.succeeded_outcomes

  extra_fields = {
    orcavaultRef = jsonencode(var.orcavault_release_ref)
    logsUrl      = "$taskArn ? '${local.logs_url_prefix}' & $split($taskArn, '/')[-1] : null"
  }

  failed_cause = "$detail.error ? $detail.error : 'The run ended with ' & $detail.outcome & ': ' & $detail.failedNodes"
}

resource "aws_cloudwatch_log_group" "states" {
  name              = "/aws/vendedlogs/states/${local.name_prefix}"
  retention_in_days = 90
}

resource "aws_sfn_state_machine" "run" {
  name     = local.name_prefix
  role_arn = aws_iam_role.states.arn
  type     = "STANDARD"

  # Only errors are logged, without the execution's data, which its history has.
  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.states.arn}:*"
    include_execution_data = false
    level                  = "ERROR"
  }

  definition = jsonencode({
    Comment       = "Runs the OrcaVault dbt project on Redshift Serverless."
    QueryLanguage = "JSONata"
    StartAt       = "CheckNoRunInProgress"

    # The states that send the event and finish are in module.finish, from ../sfn-finish.
    States = merge(module.finish.states, {
      # Overlapping runs are not safe so ensure that there is no concurrent executions.
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
            Assign      = { detail = local.no_runner_event_detail["check_failed"], taskArn = null }
            Next        = "AddRunFields"
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
        Assign  = { detail = local.no_runner_event_detail["run_in_progress"], taskArn = null }
        Next    = "AddRunFields"
      }

      # The .sync integration waits for the task to stop, and fails this state
      # if the runner exits non-zero.
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
                # downstream is for the state machine, not the runner, which only takes args.
                Environment = [
                  { Name = "ORCAVAULT_RUN_ID", Value = "{% $states.context.Execution.Name %}" },
                  { Name = "ORCAVAULT_RUN_REQUEST", Value = "{% $string($states.context.Execution.Input ~> |$|{}, ['downstream']|) %}" },
                ]
              }
            ]
          }
        }

        # Only failures to start the task are retried, such as throttling or no
        # Fargate capacity.
        Retry = [
          {
            ErrorEquals     = ["ECS.AmazonECSException", "AmazonECS.Unknown"]
            IntervalSeconds = 60
            MaxAttempts     = 3
            BackoffRate     = 2
          }
        ]
        Assign = { taskArn = "{% $states.result.TaskArn %}" }
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Assign = {
              taskArn = trimspace(<<-EOT
                {% ($task := $match($states.errorOutput.Cause, /"TaskArn"\s*:\s*"([^"]+)"/, 1); $task ? $task[0].groups[0] : null) %}
              EOT
              )
            }
            Next = "ReadEvent"
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
          # A timed out task is stopped without waiting, which means the runner
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
            Next        = "AddRunFields"
          }
        ]
        Next = "AddRunFields"
      }
    })
  })

  # Creating the state machine checks that the role can deliver its logs.
  depends_on = [aws_iam_role_policy.states]
}

# Starts the run after the sources stage, when the chain continues with {"downstream": true}.
resource "aws_cloudwatch_event_rule" "start" {
  name           = "${local.name_prefix}-start"
  description    = "Starts the OrcaVault ${var.environment} run after ${var.start_after.detail_type} with ${join(" or ", var.start_after.outcomes)}"
  event_bus_name = "default"

  event_pattern = jsonencode({
    source        = [var.start_after.source]
    "detail-type" = [var.start_after.detail_type]
    detail = {
      environment = [var.environment]
      downstream  = [true]
      outcome     = var.start_after.outcomes
    }
  })
}

resource "aws_cloudwatch_event_target" "start" {
  rule           = aws_cloudwatch_event_rule.start.name
  event_bus_name = "default"
  target_id      = "state-machine"
  arn            = aws_sfn_state_machine.run.arn
  role_arn       = aws_iam_role.start.arn

  # A plain dbt build, which continues the chain on to publishing.
  input = jsonencode({ downstream = true })

  # Retries starting the execution, not the run itself.
  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 5
  }
}
