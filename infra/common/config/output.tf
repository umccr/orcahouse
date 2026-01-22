output "warehouse_name" {
  value = "orcahouse"
}

output "warehouse_db_cluster_name" {
  value = "orcahouse-db"
}

output "warehouse_vault_db_name" {
  value = "orcavault"
}

output "orcabus_bus_name" {
  value = "OrcaBusMain"
}

output "main_vpc_id" {
  value = data.aws_vpc.main_vpc.id
}

output "orcahouse_db_sg_id" {
  # The security group is created and controlled by main db stack at ../aurora/
  # After main db stack has been deployed, we set the following sg value statically.
  value = {
    default = "sg-mock-for-testing"
    dev     = "sg-000a9854f4f3e564e"
    prod    = "sg-013b6e66086adc6a6"
    stg     = ""
  }
}

output "main_vpc_private_subnet_ids" {
  value = data.aws_subnets.private.ids
}

output "lambda_vpc_access_policy_arn" {
  value = data.aws_iam_policy.lambda_vpc_access.arn
}
