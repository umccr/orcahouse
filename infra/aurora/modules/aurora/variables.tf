variable "stack_name" {
  description = "The stack name used to prefix resource names and lookup SSM parameters."
  type        = string
  default     = "orcanexus"
}

variable "environment" {
  description = "The environment name (e.g. dev, prod)."
  type        = string
}

variable "engine_version" {
  description = "The Aurora PostgreSQL engine version."
  type        = string
  default     = "18.6"
}

variable "min_capacity" {
  description = "Serverless v2 minimum ACU capacity."
  type        = number
  default     = 0.5
}

variable "max_capacity" {
  description = "Serverless v2 maximum ACU capacity."
  type        = number
  default     = 16.0
}

variable "backup_retention_period" {
  description = "The days to retain backups for."
  type        = number
  default     = 7
}

variable "deletion_protection" {
  description = "Whether the cluster has deletion protection enabled. Flip to false and apply first before tearing down."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Whether to skip the final snapshot on cluster deletion. Flip to true and apply first before tearing down."
  type        = bool
  default     = false
}
