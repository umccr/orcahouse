variable "environment" {
  description = "Deployment environment (dev or prod). Drives rule name prefixes (orcahouse-notify-<env>-), the Glue job name prefix, title tags and keywords."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be \"dev\" or \"prod\"."
  }
}

variable "topic_arn" {
  description = "ARN of the Slack SNS topic the matched events are delivered to."
  type        = string
}

variable "publisher_role_arn" {
  description = "ARN of the EventBridge publisher role assumed to publish to the topic."
  type        = string
}

variable "dlq_arn" {
  description = "ARN of the SQS dead-letter queue that receives events the targets could not deliver."
  type        = string
}

variable "dms_replication_instance_ids" {
  description = "DMS replication instance identifiers to alert on. Each gets its own dms-<identifier> rule. Leave empty to skip."
  type        = list(string)
  default     = []
}

variable "dms_replication_task_ids" {
  description = "DMS replication task identifiers to alert on. Each gets its own dms-<identifier> rule. Leave empty to skip."
  type        = list(string)
  default     = []
}

variable "crawler_names" {
  description = "Exact Glue crawler names to alert on. Leave empty to skip the crawler-failed and crawler-start-failed rules."
  type        = list(string)
  default     = []
}

variable "disabled_rules" {
  description = "Rule keys to create in the DISABLED state, e.g. during a maintenance window or the OrcaGlue cutover. Keys are the rule names without the orcahouse-notify-<env>- prefix, as listed in the rule_names output (e.g. glue-job-failure, dms-orcabus-db-task-filemanager)."
  type        = set(string)
  default     = []

  validation {
    condition     = length(setsubtract(var.disabled_rules, keys(local.rules))) == 0
    error_message = "disabled_rules contains a key that is not a rule in this environment. Valid keys: ${join(", ", sort(keys(local.rules)))}."
  }
}
