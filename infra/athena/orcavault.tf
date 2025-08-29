locals {
  # https://docs.aws.amazon.com/athena/latest/ug/understanding-tables-databases-and-the-data-catalog.html
  catalog_name = "orcavault"
}

resource "aws_serverlessapplicationrepository_cloudformation_stack" "orcavault" {
  name             = "AthenaPostgreSQLConnectorForOrcaVault"
  application_id   = data.aws_serverlessapplicationrepository_application.this.id
  semantic_version = data.aws_serverlessapplicationrepository_application.this.semantic_version
  capabilities     = data.aws_serverlessapplicationrepository_application.this.required_capabilities

  # https://docs.aws.amazon.com/athena/latest/ug/connectors-postgresql.html
  # https://github.com/awslabs/aws-athena-query-federation/blob/cd2fa85/athena-postgresql/athena-postgresql.yaml
  parameters = {
    DefaultConnectionString = "postgres://jdbc:postgresql://${data.aws_rds_cluster.orcahouse_db.reader_endpoint}:5432/${local.catalog_name}?$${${data.aws_secretsmanager_secret.ro.name}}"
    LambdaFunctionName      = local.catalog_name
    SecretNamePrefix        = data.aws_secretsmanager_secret.ro.name
    SpillBucket             = data.aws_s3_bucket.staging_data.bucket
    SecurityGroupIds        = module.config.orcahouse_db_sg_id[terraform.workspace],

    SubnetIds = join(",", data.aws_subnets.private_subnets_ids.ids)
  }

  # uncomment to update latest connector version
  lifecycle {
    ignore_changes = [semantic_version,]
  }
}

resource "aws_athena_data_catalog" "orcavault" {
  name        = local.catalog_name
  description = "${local.stack_name} athena data catalog: ${local.catalog_name}"
  type        = "LAMBDA"

  parameters = {
    "function" = "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${local.catalog_name}"
  }
}
