# The Step Functions definition that loads the sources the run reads, and the schedule that
# starts the nightly chain with it.

locals {
  # A DMS task that isn't running means its CDC is going stale. It doesn't stop the stage,
  # which still crawls whatever DMS has written.
  dms_tasks_not_running = replace(trimspace(<<-EOT
    {% { 'dmsTasksNotRunning': [${jsonencode(var.dms_replication_task_ids)}.(
      $id := $;
      $task := $states.result.ReplicationTasks[ReplicationTaskIdentifier = $id];
      $not($task.Status = 'running') ? $id & ' (' & ($exists($task.Status) ? $task.Status : 'not found') & ')'
    )] } %}
  EOT
  ), "\n", " ")

  # A failed job's state is in the cause of a .sync error, otherwise the error says why
  # it didn't run, such as Glue.ConcurrentRunsExceededException.
  glue_job_failed = replace(trimspace(<<-EOT
    {% { 'job': $states.input, 'status': (
      $cause := $states.errorOutput.Cause;
      $found := $type($cause) = 'string' ? $match($cause, /"JobRunState"\s*:\s*"([A-Z_]+)"/);
      $found ? $found[0].groups[0] : $states.errorOutput.Error
    ) } %}
  EOT
  ), "\n", " ")

  # The event detail from the CDC and TSA branches' outputs.
  loaded_detail = replace(trimspace(<<-EOT
    {% (
      $cdc := $states.result[0];
      $tsa := $states.result[1];
      $failedCrawls := $cdc.crawls[status != 'SUCCEEDED'];
      $failedJobs := $tsa.jobs[status != 'SUCCEEDED'];
      {
        'outcome': $count($cdc.dmsTasksNotRunning) + $count($failedCrawls) + $count($failedJobs) > 0 ? 'degraded' : 'succeeded',
        'error': null,
        'dmsTasksNotRunning': $join($cdc.dmsTasksNotRunning, ', '),
        'crawlersSucceeded': $count($cdc.crawls[status = 'SUCCEEDED']),
        'crawlersFailed': $count($failedCrawls),
        'failedCrawlers': $join([$failedCrawls.(crawler & ' (' & status & ')')], ', '),
        'jobsSucceeded': $count($tsa.jobs[status = 'SUCCEEDED']),
        'jobsFailed': $count($failedJobs),
        'failedJobs': $join([$failedJobs.(job & ' (' & status & ')')], ', ')
      }
    ) %}
  EOT
  ), "\n", " ")

  # The stage itself broke, rather than a source.
  error_detail = {
    outcome            = "error"
    error              = "Loading the sources failed unexpectedly. Check the execution for details"
    dmsTasksNotRunning = ""
    crawlersSucceeded  = 0
    crawlersFailed     = 0
    failedCrawlers     = ""
    jobsSucceeded      = 0
    jobsFailed         = 0
    failedJobs         = ""
  }

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

resource "aws_sfn_state_machine" "sources" {
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
    Comment       = "Loads the sources that the OrcaVault ${var.environment} run reads."
    QueryLanguage = "JSONata"
    StartAt       = "LoadSources"

    States = merge(module.finish.states, {
      # The CDC and TSA sources don't depend on each other, so they load at the same time.
      LoadSources = {
        Type = "Parallel"
        Branches = [
          {
            StartAt = "CheckDms"
            States = {
              CheckDms = {
                Type     = "Task"
                Resource = "arn:aws:states:::aws-sdk:databasemigration:describeReplicationTasks"
                Arguments = {
                  Filters         = [{ Name = "replication-task-id", Values = var.dms_replication_task_ids }]
                  WithoutSettings = true
                }
                Output = local.dms_tasks_not_running
                Retry  = [local.retry_api_errors]
                Catch = [
                  {
                    ErrorEquals = ["States.ALL"]
                    Output      = "{% { 'dmsTasksNotRunning': ['DMS check failed with ' & $states.errorOutput.Error] } %}"
                    Next        = "CrawlCdc"
                  }
                ]
                Next = "CrawlCdc"
              }

              CrawlCdc = {
                Type          = "Map"
                Items         = module.crawl.items
                ItemProcessor = module.crawl.item_processor
                Output        = "{% $merge([$states.input, { 'crawls': $states.result }]) %}"
                End           = true
              }
            }
          },
          {
            StartAt = "FindGlueJobs"
            States = {
              # Far fewer than MaxResults jobs are tagged, so there's no next page.
              FindGlueJobs = {
                Type     = "Task"
                Resource = "arn:aws:states:::aws-sdk:glue:listJobs"
                Arguments = {
                  Tags       = local.glue_job_stage_tag
                  MaxResults = 1000
                }
                Output = "{% [$states.result.JobNames[$substring($, 0, ${length(local.glue_job_name_prefix)}) = '${local.glue_job_name_prefix}']] %}"
                Retry  = [local.retry_api_errors]
                Catch = [
                  {
                    ErrorEquals = ["States.ALL"]
                    Output      = "{% { 'jobs': [{ 'job': '${local.glue_job_name_prefix}*', 'status': 'NOT_LISTED' }] } %}"
                    Next        = "GlueJobsNotListed"
                  }
                ]
                Next = "RunGlueJobs"
              }

              GlueJobsNotListed = {
                Type = "Pass"
                End  = true
              }

              # One at a time, so the jobs don't contend on the Redshift workgroup.
              RunGlueJobs = {
                Type           = "Map"
                Items          = "{% $states.input %}"
                MaxConcurrency = 1
                ItemProcessor = {
                  StartAt = "RunGlueJob"
                  States = {
                    # A failed job isn't retried, the same as a scheduled job.
                    RunGlueJob = {
                      Type           = "Task"
                      Resource       = "arn:aws:states:::glue:startJobRun.sync"
                      TimeoutSeconds = 3600
                      Arguments      = { JobName = "{% $states.input %}" }
                      Output         = "{% { 'job': $states.input, 'status': $states.result.JobRunState } %}"
                      Catch = [
                        {
                          ErrorEquals = ["States.ALL"]
                          Output      = local.glue_job_failed
                          Next        = "GlueJobFinished"
                        }
                      ]
                      Next = "GlueJobFinished"
                    }

                    GlueJobFinished = {
                      Type = "Pass"
                      End  = true
                    }
                  }
                }
                Output = "{% { 'jobs': $states.result } %}"
                End    = true
              }
            }
          }
        ]
        Assign = { detail = local.loaded_detail }
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Assign      = { detail = local.error_detail }
            Next        = module.finish.start_at
          }
        ]
        Next = module.finish.start_at
      }
    })
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
    arn      = aws_sfn_state_machine.sources.arn
    role_arn = aws_iam_role.scheduler.arn

    # The scheduled chain continues on to the run.
    input = jsonencode({ downstream = true })

    # Retries starting the execution, not the stage itself.
    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 5
    }
  }
}
