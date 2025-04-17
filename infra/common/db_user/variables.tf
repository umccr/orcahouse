variable "rotation_app_name" {
  description = "Name of the serverless stack deployment managing the secret rotation"
  type        = string
}

variable "db_user_ssm_parameter" {
	description = "Name of the SSM parameter from where to read the DB username"
	type = string
}

variable "secret_name" {
	description = "Name of the secret that will hold the DB credentials"
	type = string
}