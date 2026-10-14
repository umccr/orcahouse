# Input variables for the module.

variable "environment" {
  description = "The environment, i.e. dev or prod."
  type        = string
}

variable "redshift_workgroup_name" {
  description = "The Redshift Serverless workgroup."
  type        = string
}

variable "ecr_repository_name" {
  description = "The ECR repository from ../../account-wide."
  type        = string
  default     = "orcavault-run-dbt"
}

variable "cdc_glue_databases" {
  description = "The Glue databases created by infra/glue-crawler/orcabus-db."
  type        = list(string)
  default = [
    "orcabus_filemanager",
    "orcabus_metadata_manager",
    "orcabus_sequence_run_manager",
    "orcabus_workflow_manager",
  ]
}

variable "cdc_bucket_name" {
  description = "The Bucket DMS writes CDC files to, created by infra/dms/orcabus-db."
  type        = string
  default     = "orcahouse-prod-landing-zone-115253169271-ap-southeast-2-an"
}

variable "cdc_s3_prefix" {
  description = "The key prefix of the CDC files in cdc_bucket_name."
  type        = string
  default     = "orcabus/v1/cdc/"
}

variable "developer_permission_sets" {
  description = "The IAM permission sets that can assume the dbt task role."
  type        = list(string)
  default     = []
}

variable "orcavault_release_ref" {
  description = "The release tag or commit of umccr/orcavault to deploy"
  type        = string
}

variable "dbt_threads" {
  description = "The number of threads to run dbt with."
  type        = number
  default     = 4
}

variable "task_cpu" {
  description = "The Fargate task CPUs"
  type        = string
  default     = "512"
}

variable "task_memory" {
  description = "The Fargate task memory in MiB."
  type        = string
  default     = "2048"
}

variable "schedule_expression" {
  description = "The schedule expression to run the orcavault task with"
  type        = string
  default     = "cron(0 3 * * ? *)"
}

variable "schedule_timezone" {
  description = "The timezone for schedule_expression."
  type        = string
  default     = "Australia/Melbourne"
}

variable "schedule_enabled" {
  description = "Set to false to pause the daily run."
  type        = bool
  default     = true
}

variable "run_timeout_hours" {
  description = "The timeout for the run task."
  type        = number
  default     = 4

  validation {
    condition     = var.run_timeout_hours > 0 && var.run_timeout_hours < 24
    error_message = "run_timeout_hours must be between 0 and 24."
  }
}

variable "max_hours_without_success" {
  description = "An alarm that triggers when no run succeeded for this many hours"
  type        = number
  default     = 30

  validation {
    condition     = var.max_hours_without_success >= 1 && var.max_hours_without_success <= 168
    error_message = "max_hours_without_success must be between 1 and 168."
  }
}

variable "results_retention_days" {
  description = "The number of days to retain the run events in the results bucket."
  type        = number
  default     = 90

  validation {
    condition     = var.results_retention_days >= 1
    error_message = "results_retention_days must be at least 1."
  }
}
