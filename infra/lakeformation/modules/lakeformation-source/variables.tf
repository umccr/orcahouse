variable "dw_account_id" {
  description = "AWS Account ID of the Data Warehouse account"
  type        = string
}

variable "consumer_account_ids" {
  description = "List of all consumer AWS account IDs"
  type        = list(string)
}

variable "database_name" {
  description = "Glue database name to share"
  type        = string
}

variable "tables" {
  description = "Map of table configurations"
  type = map(object({
    excluded_columns = optional(list(string), [])
    included_columns = optional(list(string), [])
    data_filters = optional(map(object({
      row_filter_expression = optional(string, null)
      included_columns      = optional(list(string), [])
      all_columns           = optional(bool, true)
    })), {})
  }))
}
