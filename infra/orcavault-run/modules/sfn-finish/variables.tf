# Input variables for the module.

variable "environment" {
  description = "The environment, i.e. dev or prod."
  type        = string
}

variable "event_source" {
  description = "The source of the event the stage sends."
  type        = string
}

variable "event_detail_type" {
  description = "The detail-type of the event the stage sends."
  type        = string
}

variable "succeeded_outcomes" {
  description = "The outcomes that end the execution as succeeded. Any other outcome fails it."
  type        = list(string)

  validation {
    condition     = length(var.succeeded_outcomes) > 0
    error_message = "succeeded_outcomes must have at least one outcome."
  }
}

variable "extra_fields" {
  description = "Fields to add to every event of this stage, as the field name and its JSONata expression."
  type        = map(string)
  default     = {}
}

variable "failed_cause" {
  description = "The JSONata expression for the cause of a failed execution."
  type        = string
  default     = "$detail.error ? $detail.error : 'The stage ended with ' & $detail.outcome"
}
