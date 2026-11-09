# The stage's definition, and the schedule that starts the nightly chain with it. The state
# machine itself comes from sfn-stage.

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

  # The event detail, from the DMS check's output and the crawls' results.
  loaded_detail = replace(trimspace(<<-EOT
    {% (
      $failedCrawls := $states.result[status != 'SUCCEEDED'];
      {
        'outcome': $count($states.input.dmsTasksNotRunning) + $count($failedCrawls) > 0 ? 'degraded' : 'succeeded',
        'error': null,
        'dmsTasksNotRunning': $join($states.input.dmsTasksNotRunning, ', '),
        'crawlersSucceeded': $count($states.result[status = 'SUCCEEDED']),
        'crawlersFailed': $count($failedCrawls),
        'failedCrawlers': $join([$failedCrawls.(crawler & ' (' & status & ')')], ', ')
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
  }

  retry_api_errors = {
    ErrorEquals     = ["States.ALL"]
    IntervalSeconds = 10
    MaxAttempts     = 3
    BackoffRate     = 2
  }

  definition = jsonencode({
    Comment       = "Loads the sources that the OrcaVault ${var.environment} run reads."
    QueryLanguage = "JSONata"
    StartAt       = "CheckDms"

    States = merge(module.finish.states, {
      # DMS replicates continuously, so its tasks are only checked, never started. A task
      # that isn't running is reported, and the crawls still crawl what DMS has written.
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

      # The upstream CDC crawlers have no schedule of their own, this stage starts them, see
      # infra/glue-crawler/orcabus-db. Other crawlers keep their own schedules.
      CrawlCdc = {
        Type          = "Map"
        Items         = module.crawl.items
        ItemProcessor = module.crawl.item_processor
        Assign        = { detail = local.loaded_detail }
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
    arn      = module.stage.state_machine_arn
    role_arn = module.stage.start_role_arn

    # The scheduled chain continues on to the run.
    input = jsonencode({ downstream = true })

    # Retries starting the execution, not the stage itself.
    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 5
    }
  }
}
