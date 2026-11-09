# Input variables for the module.

variable "environment" {
  description = "The environment, i.e. dev or prod."
  type        = string
}

variable "start_after" {
  description = "The event of the stage this one starts after, and its outcomes that start it, from that stage's event output."
  type = object({
    source      = string
    detail_type = string
    outcomes    = list(string)
  })
}

variable "max_hours_without_success" {
  description = "An alarm that triggers when no publish execution succeeded for this many hours."
  type        = number
  default     = 30

  validation {
    condition     = var.max_hours_without_success >= 1 && var.max_hours_without_success <= 168
    error_message = "max_hours_without_success must be between 1 and 168."
  }
}
