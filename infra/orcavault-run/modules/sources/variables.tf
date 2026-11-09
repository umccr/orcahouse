# Input variables for the module.

variable "environment" {
  description = "The environment, i.e. dev or prod."
  type        = string
}

variable "dms_replication_task_ids" {
  description = "The DMS tasks that write the CDC files, created by infra/dms/orcabus-db. Both environments read the same CDC."
  type        = list(string)
  default = [
    "orcabus-db-task-filemanager",
    "orcabus-db-task-metadata-manager",
    "orcabus-db-task-sequence-run-manager",
    "orcabus-db-task-workflow-manager",
  ]
}

variable "cdc_crawler_names" {
  description = "The Glue crawlers for the CDC files, created by infra/glue-crawler/orcabus-db. Both environments start them."
  type        = list(string)
  default = [
    "orcabus-db-crawler-filemanager",
    "orcabus-db-crawler-metadata-manager",
    "orcabus-db-crawler-sequence-run-manager",
    "orcabus-db-crawler-workflow-manager",
  ]
}

variable "crawl_max_wait_minutes" {
  description = "How long to wait for each crawl before reporting it as TIMEOUT."
  type        = number
  default     = 60
}

variable "schedule_expression" {
  description = "The schedule expression that starts the nightly chain."
  type        = string
  default     = "cron(0 3 * * ? *)"
}

variable "schedule_timezone" {
  description = "The timezone for schedule_expression."
  type        = string
  default     = "Australia/Melbourne"
}

variable "schedule_enabled" {
  description = "Set to false to pause the nightly chain."
  type        = bool
  default     = true
}

variable "max_hours_without_success" {
  description = "An alarm that triggers when no sources execution succeeded for this many hours."
  type        = number
  default     = 30

  validation {
    condition     = var.max_hours_without_success >= 1 && var.max_hours_without_success <= 168
    error_message = "max_hours_without_success must be between 1 and 168."
  }
}
