# Failed and timed-out runs of orcaglue-<env>-* Glue jobs. Created in every environment.
# STOPPED (a manual cancel) is left out on purpose.

locals {
  glue_job_rules = {
    "glue-job-failure" = {
      description = "Send FAILED and TIMEOUT runs of orcaglue-${var.environment}-* Glue jobs to the Slack SNS topic"

      event_pattern = jsonencode({
        source        = ["aws.glue"]
        "detail-type" = ["Glue Job State Change"]
        detail = {
          jobName = [{ prefix = "orcaglue-${var.environment}-" }]
          state   = ["FAILED", "TIMEOUT"]
        }
      })

      input_paths = {
        account  = "$.account"
        region   = "$.region"
        time     = "$.time"
        jobName  = "$.detail.jobName"
        jobRunId = "$.detail.jobRunId"
        state    = "$.detail.state"
      }

      input_template = jsonencode({
        version = "1.0"
        source  = "custom"
        content = {
          textType    = "client-markdown"
          title       = ":rotating_light: [${var.environment}] Glue job <state>: <jobName>"
          description = "*Run ID:* `<jobRunId>`\n*Account:* ${local.account_name} (<account>, <region>)\n*Time (UTC):* <time>"
          nextSteps   = ["Error and logs: https://<region>.console.aws.amazon.com/gluestudio/home?region=<region>#/job/<jobName>/run/<jobRunId>"]
          keywords    = ["OrcaHouse", var.environment, "<state>"]
        }
      })
    }
  }
}
