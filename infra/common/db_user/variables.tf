variable "stack_name" {
  description = "Name of the stack"
  type        = string
}

variable "db_cluster_name" {
  description = "The name of the DB cluster"
  type = string
  default = "orcahouse-db"
}

variable "db_name" {
  description = "The name of the Database"
  type        = string
  default     = "orcavault"
}

variable "db_user_ssm_parameter" {
	description = "Name of the SSM parameter from where to read the DB username"
	type = string
}

variable "secret_name" {
	description = "Name of the secret that will hold the DB credentials"
	type = string
}