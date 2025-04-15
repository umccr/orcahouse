# Variables

variable "service_id" {
  description = "A short unique identifier for the service. Will be used in resource naming."
  type = string
}

variable "db_secret_name" {
  description = "Name of the Secrets Manager secret holding the DB credentials"
  type        = string
}

variable "event_pattern" {
  description = "The event pattern to use for the EventBridge Rule"
  type = object({
    detail-type = list(string),
    source = list(string)
  })
}

variable "iam_path" {
  description = "Path to use for IAM resources"
  type        = string
  default     = "/"
}

variable "lambda_function_name" {
  description = "Path to the Lambda source directory"
  type        = string
}

variable "lambda_function_handler" {
  description = "Path to the Lambda source directory"
  type        = string
}

variable "lambda_source_dir" {
  description = "Path to the Lambda source directory"
  type        = string
}

variable "lambda_artefact_out_path" {
  description = "Path to the Lambda source directory"
  type        = string
}

variable "lambda_layers" {
  description = "ARNs of Lambda layer to attach"
  type        = list(string)
}


