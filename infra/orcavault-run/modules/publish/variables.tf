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
  description = "An alarm that triggers when no publish execution succeeded for this many hours. sfn-stage validates the range."
  type        = number
  default     = 30
}
