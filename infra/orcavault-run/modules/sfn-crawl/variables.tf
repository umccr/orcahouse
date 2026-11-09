# Input variables for the module.

variable "crawler_names" {
  description = "The Glue crawlers the Map crawls, which are its items. Can be empty."
  type        = list(string)
}

variable "poll_seconds" {
  description = "How often to check whether a crawl has finished."
  type        = number
  default     = 60

  validation {
    condition     = var.poll_seconds >= 10
    error_message = "poll_seconds must be at least 10."
  }
}

variable "max_wait_minutes" {
  description = "How long to wait for a crawl before reporting it as TIMEOUT."
  type        = number
  default     = 60

  validation {
    condition     = var.max_wait_minutes >= 1
    error_message = "max_wait_minutes must be at least 1."
  }
}
