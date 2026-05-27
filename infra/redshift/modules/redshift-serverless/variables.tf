variable "namespace_name" {
  type = string
}

variable "workgroup_name" {
  type = string
}

variable "db_name" {
  type = string
}

variable "base_capacity" {
  description = "RPU capacity for the workgroup"
  type        = number
  default     = 4
}

variable "max_capacity" {
  description = "RPU capacity for the workgroup"
  type        = number
  default     = 4
}

variable "environment" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "compute_limit_amount" {
  description = "RPU consumed per hour for the workgroup"
  type        = number
  default     = 60
}

variable "data_limit_amount" {
  description = "Terabytes (TB) of data transferred between Regions in cross-account sharing"
  type        = number
  default     = 1 # TB
}

variable "glue_database_arns" {
  description = "List of Glue database ARNs the namespace IAM role can access"
  type        = list(string)
  default     = ["*"]
}

variable "s3_bucket_arns" {
  description = "List of S3 bucket ARNs backing the Glue tables (include both bucket and prefix ARNs)"
  type        = list(string)
  default     = ["*"]
}
