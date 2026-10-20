# OrcaVault dbt runs that did not succeed, from the OrcaVaultRunFinished event the
# orcavault-run state machine (infra/orcavault-run) sends at the end of every execution.
# Created in every environment. Dev and prod send to the same default bus, so
# detail.environment selects this environment's runs. warned is a successful run and is
# left out on purpose.
# Unlike the other rules, these templates use free text (error, failedNodes). The runner
# writes it on one line without double quotes or backslashes (one_line in
# infra/orcavault-run/docker/runner/orcavault_runner/run.py), and the state machine's own
# errors are fixed strings, so it is safe to insert unescaped.
# There are two rules so that every placeholder is always set: failed always has logsUrl
# and a null error; error and skipped always have an error, but logsUrl can be null.

locals {
  orcavault_run_input_paths = {
    account      = "$.account"
    region       = "$.region"
    time         = "$.time"
    runId        = "$.detail.runId"
    outcome      = "$.detail.outcome"
    orcavaultRef = "$.detail.orcavaultRef"
    duration     = "$.detail.durationMinutes"
    executionUrl = "$.detail.executionUrl"
  }

  orcavault_run_footer = "*OrcaVault ref:* `<orcavaultRef>`\n*Duration:* <duration> min\n*Account:* ${local.account_name} (<account>, <region>)\n*Time (UTC):* <time>"

  orcavault_run_rules = {
    "orcavault-run-failed" = {
      description = "Send failed OrcaVault ${var.environment} dbt runs to the Slack SNS topic"

      event_pattern = jsonencode({
        source        = ["orcahouse.orcavault"]
        "detail-type" = ["OrcaVaultRunFinished"]
        detail = {
          environment = [var.environment]
          outcome     = ["failed"]
        }
      })

      input_paths = merge(local.orcavault_run_input_paths, {
        modelsFailed  = "$.detail.modelsFailed"
        modelsSkipped = "$.detail.modelsSkipped"
        testsFailed   = "$.detail.testsFailed"
        failedNodes   = "$.detail.failedNodes"
        logsUrl       = "$.detail.logsUrl"
      })

      input_template = jsonencode({
        version = "1.0"
        source  = "custom"
        content = {
          textType    = "client-markdown"
          title       = ":rotating_light: [${var.environment}] OrcaVault dbt run failed"
          description = "*Process:* OrcaVault dbt run\n*Run ID:* `<runId>`\n*Models:* <modelsFailed> failed, <modelsSkipped> skipped\n*Tests:* <testsFailed> failed\n*Failed nodes:* <failedNodes>\n${local.orcavault_run_footer}"
          nextSteps   = ["Logs: <logsUrl>", "Execution: <executionUrl>"]
          keywords    = ["OrcaHouse", var.environment, "dbt"]
        }
      })
    }

    "orcavault-run-error" = {
      description = "Send OrcaVault ${var.environment} dbt runs that errored or were skipped to the Slack SNS topic"

      event_pattern = jsonencode({
        source        = ["orcahouse.orcavault"]
        "detail-type" = ["OrcaVaultRunFinished"]
        detail = {
          environment = [var.environment]
          outcome     = ["error", "skipped"]
        }
      })

      input_paths = merge(local.orcavault_run_input_paths, {
        error = "$.detail.error"
      })

      input_template = jsonencode({
        version = "1.0"
        source  = "custom"
        content = {
          textType    = "client-markdown"
          title       = ":rotating_light: [${var.environment}] OrcaVault dbt run <outcome>"
          description = "*Process:* OrcaVault dbt run\n*Run ID:* `<runId>`\n*Reason:* <error>\n${local.orcavault_run_footer}"
          nextSteps   = ["Execution: <executionUrl>"]
          keywords    = ["OrcaHouse", var.environment, "dbt", "<outcome>"]
        }
      })
    }
  }
}
