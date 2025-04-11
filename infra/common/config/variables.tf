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