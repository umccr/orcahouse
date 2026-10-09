variable "environment" {
  description = "Deployment environment (dev or prod). Used in resource names, SSM paths, and the SourceArn rule-name prefix."
  type        = string
}

variable "slack_topic_arn" {
  description = "ARN of the cross-account Slack SNS topic this environment's publisher role may publish to."
  type        = string
}
