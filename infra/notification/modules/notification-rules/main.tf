# EventBridge rules and Slack targets for one environment. Each source file defines a map
# of rules (glue_job.tf, alarm.tf, dms.tf, crawler.tf); this file creates them. Templates
# never use free-text event fields (error messages): EventBridge inserts values unescaped,
# so a quote or newline would break the JSON and Amazon Q would drop the message.

locals {
  account_name = "umccr-warehouse-prod"

  rules = merge(local.glue_job_rules, local.alarm_rules, local.dms_rules, local.crawler_rules)
}

resource "aws_cloudwatch_event_rule" "this" {
  for_each = local.rules

  name           = "orcahouse-notify-${var.environment}-${each.key}"
  description    = each.value.description
  event_bus_name = "default"
  event_pattern  = each.value.event_pattern
  state          = contains(var.disabled_rules, each.key) ? "DISABLED" : "ENABLED"
}

resource "aws_cloudwatch_event_target" "this" {
  for_each = local.rules

  rule           = aws_cloudwatch_event_rule.this[each.key].name
  event_bus_name = "default"
  target_id      = "slack-sns-topic"
  arn            = var.topic_arn
  role_arn       = var.publisher_role_arn

  # Retry for 1 hour, not the default 24, so a stuck alert reaches the DLQ alarm quickly.
  dead_letter_config {
    arn = var.dlq_arn
  }

  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 185
  }

  input_transformer {
    input_paths = each.value.input_paths

    # jsonencode() escapes < and > as \u003c and \u003e; EventBridge needs literal
    # <placeholder> tokens. See https://github.com/hashicorp/terraform/issues/38733
    input_template = replace(replace(each.value.input_template, "\\u003c", "<"), "\\u003e", ">")
  }
}
