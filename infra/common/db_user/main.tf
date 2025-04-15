
################################################################################
# general config

data "aws_partition" "current" {}

data "aws_region" "current" {}

module "common" {
  source = "../config"
}

################################################################################
# data sources

# AWS managed Serverless Application template
data "aws_serverlessapplicationrepository_application" "this" {
  # We leverage SAM serverless repo CloudFormation stack for secret rotation.
  # These rotation Lambda templates are developed, maintained and provided by AWS.
  # https://docs.aws.amazon.com/secretsmanager/latest/userguide/reference_available-rotation-templates.html
  # https://serverlessrepo.aws.amazon.com/applications/us-east-1/297356227824/SecretsManagerRDSPostgreSQLRotationSingleUser
  application_id = "arn:aws:serverlessrepo:us-east-1:297356227824:applications/SecretsManagerRDSPostgreSQLRotationSingleUser"
}

# Generate a random password
data "aws_secretsmanager_random_password" "this" {
  password_length    = 50
  exclude_characters = "\"#$%&'()*+,-./:;<=>?[\\]^_`{|}~."
}

# load the actual DB username from SSM parameter store
data "aws_ssm_parameter" "db_username" {
  # name = "/${local.stack_name}/ro_username"
  name = var.db_user_ssm_parameter
}

# Get details about the DB Cluster
data "aws_rds_cluster" "orcahouse_db" {
  cluster_identifier = var.db_cluster_name
}

################################################################################
# resourced definition for secret rotation

# CloudFormation stack for secret rotation
resource "aws_serverlessapplicationrepository_cloudformation_stack" "this" {
  # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/serverlessapplicationrepository_cloudformation_stack
  # https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-secretsmanager-rotationschedule-hostedrotationlambda.html
  # https://docs.aws.amazon.com/secretsmanager/latest/userguide/asm_access.html#endpoints

  name             = var.stack_name
  application_id   = data.aws_serverlessapplicationrepository_application.this.application_id
  semantic_version = data.aws_serverlessapplicationrepository_application.this.semantic_version
  capabilities     = data.aws_serverlessapplicationrepository_application.this.required_capabilities

  parameters = {
    endpoint            = "https://secretsmanager.${data.aws_region.current.name}.${data.aws_partition.current.dns_suffix}"
    functionName        = var.stack_name
    vpcSubnetIds        = join(",", sort(module.common.main_vpc_private_subnet_ids))
    vpcSecurityGroupIds = join(",", sort([module.common.orcahouse_db_sg_id[terraform.workspace]]))
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

# Create a secret in AWS Secrets Manager for the DB user
resource "aws_secretsmanager_secret" "secret" {
  name                    = var.secret_name
  recovery_window_in_days = 7
}

# Populate the secret with connction details and initial password
# NOTE: the password will be changed by the secret rotation
resource "aws_secretsmanager_secret_version" "secret" {
  secret_id = aws_secretsmanager_secret.secret.id

  secret_string = jsonencode(
    {
      engine   = "postgres"
      host     = data.aws_rds_cluster.orcahouse_db.reader_endpoint  # intended
      username = data.aws_ssm_parameter.db_username.value
      password = data.aws_secretsmanager_random_password.this.random_password  # initial password only
      dbname   = var.db_name
      port     = 5432
    }
  )

  # NOTE: Only needed on the very first time deployment. The secret rotation will rotate the secret then on.
  lifecycle {
    ignore_changes = [secret_string,]
  }
}

resource "aws_secretsmanager_secret_rotation" "secret" {
  secret_id           = aws_secretsmanager_secret_version.secret.secret_id
  rotation_lambda_arn = aws_serverlessapplicationrepository_cloudformation_stack.this.outputs.RotationLambdaARN

  rotation_rules {
    automatically_after_days = 1
  }
}
