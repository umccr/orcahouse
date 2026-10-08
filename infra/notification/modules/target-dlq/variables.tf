variable "environment" {
  description = "Deployment environment (dev or prod). Used in resource names, the SSM path, and the SourceArn rule-name prefix."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be \"dev\" or \"prod\"."
  }
}
