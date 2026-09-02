variable "dw_account_id" {
  description = "AWS Account ID of the Data Warehouse account"
  type        = string
}

variable "database_resource_links" {
  description = "Map of local database name to source database name in warehouse account"
  type        = map(string)
}
