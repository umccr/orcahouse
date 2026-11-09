# The Step Functions run definition for the orcavault runner. Each run crawls the CDC,
# builds the dbt project, and sends the run event, or does only the steps its input lists.

locals {
  run_timeout_seconds = var.run_timeout_hours * 3600
  crawl_max_wait_ms   = var.crawl_max_wait_minutes * 60000

  # This defines the steps that a run can do in the required order.
  steps = ["crawl", "dbt"]

  # Warning is a successful outcome because models were still applied correctly.
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

  run_in_progress_detail = merge(local.empty_event_detail, {
    outcome = "skipped"
    error   = "Another OrcaVault dbt task was still running, so this run didn't start"
  })

  no_event_detail = merge(local.empty_event_detail, {
    outcome = "error"
    error   = "The runner wrote no event. The task may have failed to start, or been killed. Check the execution for details"
  })

  # The run's detail, i.e. the runner's event or one of the above, and the fields every run
  # event has.
  event_detail = "{% $merge([$detail, $states.input]) %}"

  retry_api_errors = {
    ErrorEquals     = ["States.ALL"]
    IntervalSeconds = 10
    MaxAttempts     = 3
    BackoffRate     = 2
  }
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
    Comment       = "Crawls the CDC, then runs the OrcaVault dbt project on Redshift Serverless."
    QueryLanguage = "JSONata"
    StartAt       = "ReadSteps"

    States = {
      ReadSteps = {
        Type    = "Pass"
        Comment = "The steps to run."
        Assign  = { steps = "{% $exists($states.input.steps) ? $states.input.steps : ${jsonencode(local.steps)} %}" }
        Next    = "ShouldCrawl"
      }

      ShouldCrawl = {
        Type = "Choice"
        Choices = [
          {
            Condition = "{% $count($steps[$not($ in ${jsonencode(local.steps)})]) > 0 %}"
            Next      = "UnknownStep"
          },
          {
            Condition = "{% 'crawl' in $steps %}"
            Next      = "CrawlCdc"
          },
        ]
        Default = "ShouldRunDbt"
      }

      UnknownStep = {
        Type  = "Fail"
        Error = "error"
        Cause = "Invalid steps specified."
      }

      # The crawls add the CDC's new partitions before dbt reads them. A crawl that fails, or
      # is still running after crawl_max_wait_minutes, doesn't stop the run.
      CrawlCdc = {
        Type  = "Map"
        Items = var.cdc_crawler_names
        ItemProcessor = {
          StartAt = "StartCrawler"
          States = {
            StartCrawler = {
              Type      = "Task"
              Resource  = "arn:aws:states:::aws-sdk:glue:startCrawler"
              Arguments = { Name = "{% $states.input %}" }
              Assign    = { crawler = "{% $states.input %}" }
              Retry     = [local.retry_api_errors]
              Catch = [
                # Another crawl is running so this waits here.
                {
                  ErrorEquals = ["Glue.CrawlerRunningException"]
                  Assign      = { crawler = "{% $states.input %}" }
                  Next        = "WaitForCrawl"
                },
                {
                  ErrorEquals = ["States.ALL"]
                  Next        = "CrawlDone"
                },
              ]
              Next = "WaitForCrawl"
            }

            WaitForCrawl = {
              Type    = "Wait"
              Seconds = 60
              Next    = "GetCrawler"
            }

            GetCrawler = {
              Type      = "Task"
              Resource  = "arn:aws:states:::aws-sdk:glue:getCrawler"
              Arguments = { Name = "{% $crawler %}" }
              Output    = "{% $states.result.Crawler.State %}"
              Retry     = [local.retry_api_errors]
              Catch = [
                {
                  ErrorEquals = ["States.ALL"]
                  Next        = "CrawlDone"
                }
              ]
              Next = "IsCrawlDone"
            }

            # The crawls are the first step, so the time since the execution started is how
            # long it has waited.
            IsCrawlDone = {
              Type = "Choice"
              Choices = [
                {
                  Condition = "{% $states.input = 'READY' or $millis() - $toMillis($states.context.Execution.StartTime) > ${local.crawl_max_wait_ms} %}"
                  Next      = "CrawlDone"
                }
              ]
              Default = "WaitForCrawl"
            }

            CrawlDone = {
              Type = "Succeed"
            }
          }
        }
        Output = {}
        Next   = "ShouldRunDbt"
      }

      ShouldRunDbt = {
        Type = "Choice"
        Choices = [
          {
            Condition = "{% 'dbt' in $steps %}"
            Next      = "CheckNoRunInProgress"
          }
        ]
        Default = "NoDbtStep"
      }

      NoDbtStep = {
        Type    = "Succeed"
        Comment = "dbt isn't one of the steps, so the execution ends without a run or its event."
      }

      # Overlapping runs are not safe so ensure that there is no concurrent executions.
      CheckNoRunInProgress = {
        Type     = "Task"
        Resource = "arn:aws:states:::aws-sdk:ecs:listTasks"
        Arguments = {
          Cluster       = aws_ecs_cluster.this.arn
          Family        = aws_ecs_task_definition.dbt.family
          DesiredStatus = "RUNNING"
        }
        Output = "{% $count($states.result.TaskArns) %}"
        Retry  = [local.retry_api_errors]
        Next   = "IsRunInProgress"
      }

      IsRunInProgress = {
        Type = "Choice"
        Choices = [
          {
            Condition = "{% $states.input > 0 %}"
            Next      = "RunInProgress"
          }
        ]
        Default = "RunDbt"
      }

      RunInProgress = {
        Type    = "Pass"
        Comment = "Another OrcaVault dbt task is still running, so this run doesn't start."
        Assign  = { detail = local.run_in_progress_detail, taskArn = null }
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
                # steps is for the state machine, not the runner, which only takes args.
                Environment = [
                  { Name = "ORCAVAULT_RUN_ID", Value = "{% $states.context.Execution.Name %}" },
                  { Name = "ORCAVAULT_RUN_REQUEST", Value = "{% $string($states.context.Execution.Input ~> |$|{}, ['steps']|) %}" },
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
            Assign      = { detail = local.no_event_detail }
            Next        = "AddRunFields"
          }
        ]
        Next = "AddRunFields"
      }

      AddRunFields = {
        Type    = "Pass"
        Comment = "The fields every run event has, including the runner fields."
        Output = {
          environment     = var.environment
          orcavaultRef    = var.orcavault_release_ref
          runId           = "{% $states.context.Execution.Name %}"
          durationMinutes = "{% $round(($millis() - $toMillis($states.context.Execution.StartTime)) / 60000) %}"
          logsUrl         = "{% $taskArn ? '${local.logs_url_prefix}' & $split($taskArn, '/')[-1] : null %}"
          executionUrl    = "{% '${local.execution_url_prefix}' & $states.context.Execution.Id %}"
        }
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
              Detail       = local.event_detail
            }
          ]
        }
        # A succeeded execution output is the event detail.
        Output = local.event_detail
        Retry  = [local.retry_api_errors]
        Next   = "Finish"
      }

      Finish = {
        Type = "Choice"
        Choices = [
          {
            Condition = "{% $detail.outcome in ${jsonencode(local.succeeded_outcomes)} %}"
            Next      = "Succeeded"
          }
        ]
        Default = "Failed"
      }

      Succeeded = {
        Type = "Succeed"
      }

      Failed = {
        Type  = "Fail"
        Error = "{% $detail.outcome %}"
        Cause = "{% $detail.error ? $detail.error : 'The run ended with ' & $detail.outcome & ': ' & $detail.failedNodes %}"
      }
    }
  })

  # Creating the state machine checks that the role can deliver its logs.
  depends_on = [aws_iam_role_policy.states]
}

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
