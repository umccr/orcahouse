variable "environment" {
  description = "Deployment environment (dev or prod). Used in resource names, SSM paths, and the SourceArn rule-name prefix."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be \"dev\" or \"prod\"."
  }
}

variable "slack_topic_arn" {
  description = "ARN of the cross-account Slack SNS topic this environment's publisher role may publish to."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:sns:ap-southeast-2:[0-9]{12}:[A-Za-z0-9_-]+$", var.slack_topic_arn))
    error_message = "slack_topic_arn must be an SNS topic ARN in ap-southeast-2."
  }
}
