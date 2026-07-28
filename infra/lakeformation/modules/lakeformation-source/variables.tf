variable "dw_account_id" {
  description = "AWS Account ID of the Data Warehouse account"
  type        = string
}

variable "consumer_accounts" {
  description = "Map of consumer account IDs to their principal ARNs"
  type = map(object({
    principal_arns = list(string)
  }))
}

variable "database_name" {
  description = "Glue database name to share"
  type        = string
}

variable "tables" {
  description = "Map of table configurations"
  type = map(object({
    data_filters = optional(map(object({
      row_filter_expression = optional(string, null)
      included_columns      = optional(list(string), [])
      excluded_columns      = optional(list(string), [])
    })), {})
  }))
}

variable "data_bucket_names" {
  description = "List of S3 bucket names backing the Glue database in the DW account"
  type        = list(string)
}
