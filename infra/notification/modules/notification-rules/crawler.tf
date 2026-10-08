# Failed runs and failed scheduled starts of the crawlers in var.crawler_names (exact
# names). Created only when the list is non-empty. AWS does not document the fields of
# the crawler state-change event; detail.crawlerName and detail.state are assumed.

locals {
  crawler_console_link = "Console: https://<region>.console.aws.amazon.com/glue/home?region=<region>#/v2/data-catalog/crawlers/view/<name>"

  crawler_rule_definitions = {
    "crawler-failed" = {
      description = "Send Failed runs of the OrcaHouse Glue crawlers to the Slack SNS topic"

      event_pattern = jsonencode({
        source        = ["aws.glue"]
        "detail-type" = ["Glue Crawler State Change"]
        detail = {
          state       = ["Failed"]
          crawlerName = var.crawler_names
        }
      })

      input_paths = {
        account = "$.account"
        region  = "$.region"
        time    = "$.time"
        name    = "$.detail.crawlerName"
        state   = "$.detail.state"
      }

      input_template = jsonencode({
        version = "1.0"
        source  = "custom"
        content = {
          textType    = "client-markdown"
          title       = ":rotating_light: [${var.environment}] Glue crawler <state>: <name>"
          description = "*Process:* Glue crawler\n*Reason:* Crawler run failed\n*Account:* ${local.account_name} (<account>, <region>)\n*Time (UTC):* <time>"
          nextSteps   = [local.crawler_console_link]
          keywords    = ["OrcaHouse", var.environment, "crawler"]
        }
      })
    }

    "crawler-start-failed" = {
      description = "Send failed scheduled invocations of the OrcaHouse Glue crawlers to the Slack SNS topic"

      event_pattern = jsonencode({
        source        = ["aws.glue"]
        "detail-type" = ["Glue Scheduled Crawler Invocation Failure"]
        detail = {
          crawlerName = var.crawler_names
        }
      })

      input_paths = {
        account = "$.account"
        region  = "$.region"
        time    = "$.time"
        name    = "$.detail.crawlerName"
      }

      input_template = jsonencode({
        version = "1.0"
        source  = "custom"
        content = {
          textType    = "client-markdown"
          title       = ":rotating_light: [${var.environment}] Glue crawler scheduled start failed: <name>"
          description = "*Process:* Glue crawler\n*Reason:* Scheduled crawler invocation failed\n*Account:* ${local.account_name} (<account>, <region>)\n*Time (UTC):* <time>"
          nextSteps   = [local.crawler_console_link]
          keywords    = ["OrcaHouse", var.environment, "crawler"]
        }
      })
    }
  }

  crawler_rules = {
    for k, v in local.crawler_rule_definitions : k => v if length(var.crawler_names) > 0
  }
}
