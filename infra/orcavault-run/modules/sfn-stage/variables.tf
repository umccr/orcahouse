# Input variables for the module.

variable "environment" {
  description = "The environment, i.e. dev or prod."
  type        = string
}

variable "name" {
  description = "The stage's name in the chain, i.e. sources or publish. Everything this module creates is named after it."
  type        = string
}

variable "definition" {
  description = "The stage's state machine definition, as JSON. The states that send its event and finish it come from sfn-finish."
  type        = string

  validation {
    condition     = can(jsondecode(var.definition))
    error_message = "definition must be a state machine definition as JSON."
  }
}

variable "starter_service" {
  description = "The service that starts this stage, i.e. scheduler.amazonaws.com for a schedule or events.amazonaws.com for an EventBridge rule."
  type        = string
}

variable "policy_statements" {
  description = "What the stage does of its own, as statements for its states role on top of sending its event and writing its logs."
  type = list(object({
    sid       = string
    effect    = optional(string, "Allow")
    actions   = list(string)
    resources = list(string)
  }))
  default = []
}

variable "source_policy_documents" {
  description = "Policy documents to merge into the states role's, such as sfn-crawl's crawlers."
  type        = list(string)
  default     = []
}

variable "max_hours_without_success" {
  description = "An alarm that triggers when no execution of this stage succeeded for this many hours."
  type        = number
  default     = 30

  validation {
    condition     = var.max_hours_without_success >= 1 && var.max_hours_without_success <= 168
    error_message = "max_hours_without_success must be between 1 and 168."
  }
}
