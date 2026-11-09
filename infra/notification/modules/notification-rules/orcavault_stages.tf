# OrcaVault sources and publish executions that did not succeed cleanly, from the
# OrcaVaultSourcesFinished and OrcaVaultPublishFinished events that the stages before and
# after the run (infra/orcavault-run) send at the end of every execution. Created in every
# environment, and matched on detail.environment like the run rules. succeeded is left out
# on purpose.
# The free text fields are crawler, job and DMS task names with their states, or the
# stage's own fixed messages, so they have no double quotes or backslashes and are safe to
# insert unescaped. The rules are split so that every placeholder is always set: degraded
# always has its lists, which can be empty, and error always has an error.
# A failed crawler or Glue job also has its own crawler-failed or glue-job-failure alert.
# The degraded alerts add that the run went ahead without it, and cover what those miss: a
# DMS task that isn't running, and a crawl that was still running after the stage's wait.

locals {
  orcavault_stage_input_paths = {
    account      = "$.account"
    region       = "$.region"
    time         = "$.time"
    runId        = "$.detail.runId"
    outcome      = "$.detail.outcome"
    duration     = "$.detail.durationMinutes"
    executionUrl = "$.detail.executionUrl"
  }

  orcavault_stage_footer = "*Duration:* <duration> min\n*Account:* ${local.account_name} (<account>, <region>)\n*Time (UTC):* <time>"

  orcavault_stage_rules = {
    "orcavault-sources-degraded" = {
      description = "Send degraded OrcaVault ${var.environment} sources executions to the Slack SNS topic"

      event_pattern = jsonencode({
        source        = ["orcahouse.orcavault"]
        "detail-type" = ["OrcaVaultSourcesFinished"]
        detail = {
          environment = [var.environment]
          outcome     = ["degraded"]
        }
      })

      input_paths = merge(local.orcavault_stage_input_paths, {
        dmsTasksNotRunning = "$.detail.dmsTasksNotRunning"
        failedCrawlers     = "$.detail.failedCrawlers"
        failedJobs         = "$.detail.failedJobs"
      })

      input_template = jsonencode({
        version = "1.0"
        source  = "custom"
        content = {
          textType    = "client-markdown"
          title       = ":warning: [${var.environment}] OrcaVault sources degraded"
          description = "*Process:* OrcaVault sources\n*Run ID:* `<runId>`\n*DMS tasks not running:* <dmsTasksNotRunning>\n*Failed crawlers:* <failedCrawlers>\n*Failed Glue jobs:* <failedJobs>\n*Effect:* the run still goes ahead, and reads these sources' data once they load\n${local.orcavault_stage_footer}"
          nextSteps   = ["Execution: <executionUrl>"]
          keywords    = ["OrcaHouse", var.environment, "sources"]
        }
      })
    }

    "orcavault-sources-error" = {
      description = "Send OrcaVault ${var.environment} sources executions that errored to the Slack SNS topic"

      event_pattern = jsonencode({
        source        = ["orcahouse.orcavault"]
        "detail-type" = ["OrcaVaultSourcesFinished"]
        detail = {
          environment = [var.environment]
          outcome     = ["error"]
        }
      })

      input_paths = merge(local.orcavault_stage_input_paths, {
        error = "$.detail.error"
      })

      input_template = jsonencode({
        version = "1.0"
        source  = "custom"
        content = {
          textType    = "client-markdown"
          title       = ":rotating_light: [${var.environment}] OrcaVault sources <outcome>"
          description = "*Process:* OrcaVault sources\n*Run ID:* `<runId>`\n*Reason:* <error>\n${local.orcavault_stage_footer}"
          nextSteps   = ["Execution: <executionUrl>"]
          keywords    = ["OrcaHouse", var.environment, "sources", "<outcome>"]
        }
      })
    }

    "orcavault-publish-degraded" = {
      description = "Send degraded OrcaVault ${var.environment} publish executions to the Slack SNS topic"

      event_pattern = jsonencode({
        source        = ["orcahouse.orcavault"]
        "detail-type" = ["OrcaVaultPublishFinished"]
        detail = {
          environment = [var.environment]
          outcome     = ["degraded"]
        }
      })

      input_paths = merge(local.orcavault_stage_input_paths, {
        failedCrawlers = "$.detail.failedCrawlers"
      })

      input_template = jsonencode({
        version = "1.0"
        source  = "custom"
        content = {
          textType    = "client-markdown"
          title       = ":warning: [${var.environment}] OrcaVault publish degraded"
          description = "*Process:* OrcaVault publish\n*Run ID:* `<runId>`\n*Failed crawlers:* <failedCrawlers>\n*Effect:* the mart was built, but its catalog is stale\n${local.orcavault_stage_footer}"
          nextSteps   = ["Execution: <executionUrl>"]
          keywords    = ["OrcaHouse", var.environment, "publish"]
        }
      })
    }

    "orcavault-publish-error" = {
      description = "Send OrcaVault ${var.environment} publish executions that errored to the Slack SNS topic"

      event_pattern = jsonencode({
        source        = ["orcahouse.orcavault"]
        "detail-type" = ["OrcaVaultPublishFinished"]
        detail = {
          environment = [var.environment]
          outcome     = ["error"]
        }
      })

      input_paths = merge(local.orcavault_stage_input_paths, {
        error = "$.detail.error"
      })

      input_template = jsonencode({
        version = "1.0"
        source  = "custom"
        content = {
          textType    = "client-markdown"
          title       = ":rotating_light: [${var.environment}] OrcaVault publish <outcome>"
          description = "*Process:* OrcaVault publish\n*Run ID:* `<runId>`\n*Reason:* <error>\n${local.orcavault_stage_footer}"
          nextSteps   = ["Execution: <executionUrl>"]
          keywords    = ["OrcaHouse", var.environment, "publish", "<outcome>"]
        }
      })
    }
  }
}
