# Variables
variable "vpc_tags" {
  description = "Tags to idenfity the VPC to deploy to"
  type        = object({
    Name  = string
    Stack = string
  })
  default = {
    Name  = "main-vpc"
    Stack = "networking"
  }
}

variable "db_secret_name" {
  description = "Name of the Secrets Manager secret holding the database credentials"
  type        = string
  default     = "orcahouse/orcavault/psa_rw"
}
