# --- Alerts.
#
# Two signals, both sent to the alerts topic:
#
# - A run ended badly: it failed, timed out, or was stopped.
# - No run has succeeded for max_hours_without_success. This catches the cases
#   the first can't see, like the schedule being disabled or never firing.
#
# Upstream health, such as DMS replication or the Glue crawlers, belongs to the
# stacks that own those pipelines.

resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-alerts"
}

data "aws_iam_policy_document" "alerts" {
  statement {
    sid       = "AllowServicePublish"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "cloudwatch.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts.json
}

# --- A run ended badly.

resource "aws_cloudwatch_event_rule" "run_failed" {
  name        = "${local.name_prefix}-failed"
  description = "An OrcaVault dbt run failed, timed out or was stopped."

  event_pattern = jsonencode({
    source      = ["aws.states"]
    detail-type = ["Step Functions Execution Status Change"]
    detail = {
      status          = ["FAILED", "TIMED_OUT", "ABORTED"]
      stateMachineArn = [aws_sfn_state_machine.run.arn]
    }
  })
}

resource "aws_cloudwatch_event_target" "run_failed" {
  rule      = aws_cloudwatch_event_rule.run_failed.name
  target_id = "sns"
  arn       = aws_sns_topic.alerts.arn

  input_transformer {
    input_paths = {
      status    = "$.detail.status"
      error     = "$.detail.error"
      execution = "$.detail.executionArn"
    }

    # Written by hand, not with jsonencode, which would escape the angle
    # brackets around the placeholders.
    input_template = "\"OrcaVault dbt run <status>, error: <error>. Execution: https://${data.aws_region.current.region}.console.aws.amazon.com/states/home?region=${data.aws_region.current.region}#/v2/executions/details/<execution> Logs: https://${data.aws_region.current.region}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.region}#logsV2:log-groups/log-group/${replace(aws_cloudwatch_log_group.dbt.name, "/", "$252F")}\""
  }
}

# --- No run has succeeded for a while.
#
# Missing data counts as breaching, because no successful execution publishes
# no datapoint at all. The alarm is in ALARM until the first run succeeds.

resource "aws_cloudwatch_metric_alarm" "no_recent_success" {
  alarm_name        = "${local.name_prefix}-no-recent-success"
  alarm_description = "No OrcaVault dbt run has succeeded in the last ${var.max_hours_without_success} hours."
  actions_enabled   = var.schedule_enabled

  namespace   = "AWS/States"
  metric_name = "ExecutionsSucceeded"
  dimensions = {
    StateMachineArn = aws_sfn_state_machine.run.arn
  }
  statistic = "Sum"
  period    = 3600

  evaluation_periods  = var.max_hours_without_success
  datapoints_to_alarm = var.max_hours_without_success
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}
