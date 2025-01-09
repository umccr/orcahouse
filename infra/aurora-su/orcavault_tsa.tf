locals {
  database_name  = "orcavault"
  tsa_stack_name = "OrcaVaultRDSSecretRotationTSA"
}

data "aws_ssm_parameter" "tsa_username" {
  name = "/${local.stack_name}/${local.database_name}/tsa_username"
}

resource "aws_serverlessapplicationrepository_cloudformation_stack" "tsa" {
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/serverlessapplicationrepository_cloudformation_stack
  # https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-secretsmanager-rotationschedule-hostedrotationlambda.html
  # https://docs.aws.amazon.com/secretsmanager/latest/userguide/asm_access.html#endpoints

  name             = local.tsa_stack_name
  application_id   = data.aws_serverlessapplicationrepository_application.this.application_id
  semantic_version = data.aws_serverlessapplicationrepository_application.this.semantic_version
  capabilities     = data.aws_serverlessapplicationrepository_application.this.required_capabilities

  parameters = {
    endpoint            = "https://secretsmanager.${data.aws_region.current.name}.${data.aws_partition.current.dns_suffix}"
    functionName        = local.tsa_stack_name
    vpcSubnetIds        = join(",", local.sorted_private_subnets)
    vpcSecurityGroupIds = join(",", sort([var.orcabus_compute_sg_id[terraform.workspace]]))
  }

  # NOTE: _pinned dependency_
  #   In order to maintain reproducible terraform ops, we have ignored upstream semantic_version release.
  #   SAM repo bumps this semantic_version and auto-release on daily basis. Hence, we ignore changes and,
  #   handle this dependency upgrade manually when needed. To detect what have been deployed against the
  #   latest version, just simply comment out this lifecycle block and perform `terraform plan`.
  lifecycle {
    ignore_changes = [semantic_version,]
  }
}

resource "aws_secretsmanager_secret" "tsa" {
  name                    = "${local.stack_name}/${local.database_name}/${data.aws_ssm_parameter.tsa_username.value}"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "tsa" {
  secret_id = aws_secretsmanager_secret.tsa.id

  secret_string = jsonencode(
    {
      engine   = "postgres"
      host     = data.aws_rds_cluster.orcahouse_db.endpoint
      username = data.aws_ssm_parameter.tsa_username.value
      password = data.aws_secretsmanager_random_password.this.random_password
      dbname   = local.database_name
      port     = 5432
    }
  )

  # NOTE: Only needed on the very first time deployment. The secret rotation will rotate the secret then on.
  lifecycle {
    ignore_changes = [secret_string,]
  }
}

resource "aws_secretsmanager_secret_rotation" "tsa" {
  secret_id           = aws_secretsmanager_secret_version.tsa.secret_id
  rotation_lambda_arn = aws_serverlessapplicationrepository_cloudformation_stack.tsa.outputs.RotationLambdaARN

  rotation_rules {
    automatically_after_days = 1
  }
}
