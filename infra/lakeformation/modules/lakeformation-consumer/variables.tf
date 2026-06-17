variable "dw_account_id" {
  description = "AWS Account ID of the Data Warehouse account"
  type        = string
}

variable "dw_database_name" {
  description = "Glue database name being shared from the DW account"
  type        = string
}

variable "this_account_id" {
  description = "This consumer account ID"
  type        = string
}

variable "this_account_database_name" {
  description = "This consumer account database name (creates LakeFormation Resource Link)"
  type        = string
}

variable "principal_grants" {
  description = "Consumer account local principals to grant access"
  type = map(object({
    tables      = list(string)
    permissions = optional(list(string), ["SELECT", "DESCRIBE"])
  }))
}
