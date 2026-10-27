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

variable "glue_databases" {
  description = "The Glue databases the task reads, i.e. the CDC databases created by infra/glue-crawler/orcabus-db, and the legacy data_portal database."
  type        = list(string)
}

variable "bucket_name" {
  description = "The bucket with the files of the glue_databases tables, i.e. the landing zone that DMS writes CDC files to, created by infra/dms/orcabus-db."
  type        = string
}

variable "s3_prefix" {
  description = "The key prefixes of the glue_database table files in bucket_name."
  type        = list(string)
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
  default     = "4096"
}

variable "task_memory" {
  description = "The Fargate task memory in MiB."
  type        = string
  default     = "8192"
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
