# Publish the topic ARN and the publisher role ARN so other stacks and
# operators can discover them without hardcoding.
resource "aws_ssm_parameter" "slack_topic_arn" {
  name        = "/orcahouse/notification/${var.environment}/slack_topic_arn"
  description = "Slack-bound SNS topic ARN for ${var.environment} OrcaHouse notifications (managed by infra/notification)"
  type        = "String"
  value       = var.slack_topic_arn
}

resource "aws_ssm_parameter" "publisher_role_arn" {
  name        = "/orcahouse/notification/${var.environment}/publisher_role_arn"
  description = "EventBridge publisher role ARN for ${var.environment} OrcaHouse notifications (managed by infra/notification)"
  type        = "String"
  value       = aws_iam_role.publisher.arn
}
