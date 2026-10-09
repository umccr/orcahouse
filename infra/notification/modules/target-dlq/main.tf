locals {
  name_prefix = "orcahouse-notify-${var.environment}"
  # Pinned, like the publisher role trust policy.
  account_id = "115253169271"
  region     = "ap-southeast-2"
}

# Holds events the notification rules could not deliver to Slack. SSE-SQS encryption
# needs no KMS permissions for EventBridge.
resource "aws_sqs_queue" "this" {
  name                      = "${local.name_prefix}-target-dlq"
  message_retention_seconds = 1209600 # 14 days, the SQS maximum
  sqs_managed_sse_enabled   = true
}

# Only this environment's notification rules may send to the queue.
data "aws_iam_policy_document" "queue" {
  statement {
    sid       = "AllowNotifyRulesToSendUndeliveredEvents"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.this.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:events:${local.region}:${local.account_id}:rule/${local.name_prefix}-*"]
    }
  }
}

resource "aws_sqs_queue_policy" "this" {
  queue_url = aws_sqs_queue.this.id
  policy    = data.aws_iam_policy_document.queue.json
}

# In ALARM until the queue is purged. No alarm actions: the alarm-firing rule forwards it
# to Slack, using the description as the message body. The description is inserted into
# JSON unescaped: no double quotes, and the two characters \n (written \\n here) mark
# a line break. The CloudWatch console shows them literally.
resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name        = "${local.name_prefix}-target-dlq-not-empty"
  alarm_description = "*Process:* Slack alert delivery\\n*Reason:* An OrcaHouse alert could not be delivered to Slack and is held in SQS queue ${aws_sqs_queue.this.name}. Check the ERROR_CODE and RULE_ARN message attributes, fix the cause, then purge the queue."

  namespace   = "AWS/SQS"
  metric_name = "ApproximateNumberOfMessagesVisible"
  dimensions = {
    QueueName = aws_sqs_queue.this.name
  }

  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  # SQS stops reporting metrics for an idle empty queue; that means nothing to deliver.
  treat_missing_data = "notBreaching"
}

resource "aws_ssm_parameter" "target_dlq_arn" {
  name        = "/orcahouse/notification/${var.environment}/target_dlq_arn"
  description = "Target DLQ ARN for ${var.environment} OrcaHouse notification rules (managed by infra/notification)"
  type        = "String"
  value       = aws_sqs_queue.this.arn
}
