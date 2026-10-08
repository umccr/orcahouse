variable "redshift_workgroup_name" {
  description = "Redshift Serverless workgroup hosting the orcavault database."
  type        = string
  default     = "orcahouse-prod"
}

variable "cdc_glue_databases" {
  description = "Glue databases holding the OrcaBus CDC tables, created by infra/glue-crawler/orcabus-db."
  type        = list(string)
  default = [
    "orcabus_filemanager",
    "orcabus_metadata_manager",
    "orcabus_sequence_run_manager",
    "orcabus_workflow_manager",
  ]
}

variable "cdc_bucket_name" {
  description = "Bucket DMS writes the OrcaBus CDC files to, see infra/dms/orcabus-db."
  type        = string
  default     = "orcahouse-prod-landing-zone-115253169271-ap-southeast-2-an"
}

variable "cdc_s3_prefix" {
  description = "Key prefix of the CDC files in cdc_bucket_name."
  type        = string
  default     = "orcabus/v1/cdc/"
}

variable "orcavault_release_ref" {
  description = <<-EOT
    Release tag or commit of umccr/orcavault baked into the image, and the ECR
    image tag. Pin a tag or commit, never a branch, so that the code behind any
    given load can be recovered from the image.
  EOT
  type        = string
}

variable "environment" {
  description = "Named in each run's event, so that notifications can tell environments apart."
  type        = string
  default     = "prod"
}

variable "dbt_threads" {
  description = <<-EOT
    How many models dbt builds at once. dbt orders them by the DAG, so this only
    controls how many independent models run in parallel. Keep it in line with
    the workgroup's RPU: more threads than the workgroup can serve just queue.
  EOT
  type        = number
  default     = 4
}

variable "task_cpu" {
  description = "Fargate task CPU units. dbt waits on Redshift, so it needs little."
  type        = string
  default     = "512"
}

variable "task_memory" {
  description = "Fargate task memory in MiB."
  type        = string
  default     = "2048"
}

variable "schedule_expression" {
  description = <<-EOT
    When the daily run starts, in schedule_timezone. The default is after the
    OrcaGlue TSA jobs and the OrcaBus Glue crawlers, so that most of the day's
    data is visible. A run doesn't need to wait for them: anything that becomes
    visible later is picked up by the next run.
  EOT
  type        = string
  default     = "cron(0 3 * * ? *)"
}

variable "schedule_timezone" {
  description = "Timezone for schedule_expression."
  type        = string
  default     = "Australia/Melbourne"
}

variable "schedule_enabled" {
  description = "Set to false to pause the daily run without removing anything."
  type        = bool
  default     = true
}

variable "run_timeout_hours" {
  description = <<-EOT
    A run that takes longer than this is stopped and reported as timed out.
    This is less than a day so that a stuck run can never overlap the next one.
  EOT
  type        = number
  default     = 4

  validation {
    condition     = var.run_timeout_hours > 0 && var.run_timeout_hours < 24
    error_message = "run_timeout_hours must be between 0 and 24."
  }
}

variable "max_hours_without_success" {
  description = <<-EOT
    Alarm when no run has succeeded for this long. This catches a run that
    never started, which the failure alerts can't see. Set it to a little more
    than a day for a daily schedule.
  EOT
  type        = number
  default     = 30

  validation {
    condition     = var.max_hours_without_success >= 1 && var.max_hours_without_success <= 168
    error_message = "max_hours_without_success must be between 1 and 168, which is CloudWatch's limit."
  }
}

variable "results_retention_days" {
  description = "How long each run's event is kept in the results bucket, to look back on."
  type        = number
  default     = 90

  validation {
    condition     = var.results_retention_days >= 1
    error_message = "results_retention_days must be at least 1."
  }
}
