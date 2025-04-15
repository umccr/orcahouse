output "warehouse_name" {
  value = "orcahouse"
}

output "orcabus_bus_name" {
  value = "OrcaBusMain"
}

output "main_vpc_id" {
  value = data.aws_vpc.main_vpc.id
}

output "orcahouse_db_sg_id" {
  value = {
    dev  = ""
    prod = "sg-013b6e66086adc6a6"
    stg  = ""
  }
}

output "main_vpc_private_subnet_ids" {
  value = data.aws_subnets.private.ids
}

output "lambda_vpc_access_policy_arn" {
  value = data.aws_iam_policy.lambda_vpc_access.arn
}