terraform {
  required_version = ">= 1.10.0"

  backend "s3" {
    bucket         = "umccr-terraform-states"
    key            = "orcahouse-app-sync/lims/terraform.tfstate"
    region         = "ap-southeast-2"
    dynamodb_table = "terraform-state-lock"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.91.0"
    }
  }
}

# ------------------------------------------------------------------------------
# AWS Providers
# ------------------------------------------------------------------------------

provider "aws" {
  region = "ap-southeast-2"

  default_tags {
    tags = {
      "umccr-org:Product" = "OrcaHouse"
      "umccr-org:Creator" = "Terraform"
      "umccr-org:Service" = "OrcaHouse"
      "umccr-org:Source"  = "https://github.com/umccr/orcahouse"
    }
  }
}

provider "aws" {
  alias  = "use1" # US-East-1
  region = "us-east-1"

  default_tags {
    tags = {
      "umccr-org:Product" = "OrcaHouse"
      "umccr-org:Creator" = "Terraform"
      "umccr-org:Service" = "OrcaHouse"
      "umccr-org:Source"  = "https://github.com/umccr/orcahouse"
    }
  }
}

# ------------------------------------------------------------------------------
# Locals
# ------------------------------------------------------------------------------

locals {
  stack_name      = "orcahouse"
  appsync_name    = "lims"
  database_name   = "orcavault"
  lims_domain     = "lims.vault.prod.umccr.org"
  list_query_name = "listLims"

  schema_file_path        = "schema.graphql"
  list_resolver_file_path = "./resolvers/list.js"

  rds_cluster_arn = "arn:aws:rds:ap-southeast-2:472057503814:cluster:orcahouse-db"
  rds_secret_arn  = "arn:aws:secretsmanager:ap-southeast-2:472057503814:secret:orcahouse/dbuser_ro-rfopB6" # pragma: allowlist secret
}

# ------------------------------------------------------------------------------
# Data Sources
# ------------------------------------------------------------------------------

data "aws_ssm_parameter" "cognito_user_pool_id" {
  name = "/data_portal/client/cog_user_pool_id"
}

data "aws_ssm_parameter" "hosted_zone_id" {
  name = "/hosted_zone/umccr/id"
}

# ------------------------------------------------------------------------------
# ACM Certificate and Validation (us-east-1 for CloudFront compatibility)
# ------------------------------------------------------------------------------

resource "aws_acm_certificate" "lims_vault_acm" {
  provider          = aws.use1
  domain_name       = local.lims_domain
  validation_method = "DNS"
}

resource "aws_route53_record" "lims_vault_validation_record" {
  for_each = {
    for dvo in aws_acm_certificate.lims_vault_acm.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = data.aws_ssm_parameter.hosted_zone_id.value
  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 300
  type            = each.value.type
}

resource "aws_acm_certificate_validation" "lims_vault_acm_validation" {
  provider                = aws.use1
  certificate_arn         = aws_acm_certificate.lims_vault_acm.arn
  validation_record_fqdns = [for record in aws_route53_record.lims_vault_validation_record : record.fqdn]
}

# ------------------------------------------------------------------------------
# AppSync GraphQL API
# ------------------------------------------------------------------------------

resource "aws_appsync_graphql_api" "orcabus_metadata" {
  name                 = local.appsync_name
  authentication_type  = "AMAZON_COGNITO_USER_POOLS"
  api_type             = "GRAPHQL"
  introspection_config = "ENABLED"
  schema               = file(local.schema_file_path)

  user_pool_config {
    user_pool_id   = data.aws_ssm_parameter.cognito_user_pool_id.value
    default_action = "ALLOW"
    aws_region     = "ap-southeast-2"
  }
}

# ------------------------------------------------------------------------------
# IAM Role and Policy for AppSync to access RDS
# ------------------------------------------------------------------------------

resource "aws_iam_role" "appsync_role" {
  name = "metadata-appsync-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = { Service = "appsync.amazonaws.com" }
      }
    ]
  })
}

resource "aws_iam_role_policy" "appsync_policy" {
  role = aws_iam_role.appsync_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["rds-data:ExecuteStatement", "rds-data:ExecuteSql"],
        Resource = ["${local.rds_cluster_arn}", "${local.rds_cluster_arn}:*"]
      },
      {
        Effect   = "Allow",
        Action   = ["secretsmanager:GetSecretValue"],
        Resource = ["${local.rds_secret_arn}", "${local.rds_secret_arn}:*"]
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# AppSync RDS Datasource
# ------------------------------------------------------------------------------

resource "aws_appsync_datasource" "rds_datasource" {
  api_id           = aws_appsync_graphql_api.orcabus_metadata.id
  name             = local.database_name
  type             = "RELATIONAL_DATABASE"
  service_role_arn = aws_iam_role.appsync_role.arn

  relational_database_config {
    http_endpoint_config {
      region                = "ap-southeast-2"
      db_cluster_identifier = local.rds_cluster_arn
      database_name         = local.database_name
      aws_secret_store_arn  = local.rds_secret_arn
    }
  }
}

# ------------------------------------------------------------------------------
# AppSync Resolvers
# ------------------------------------------------------------------------------

resource "aws_appsync_resolver" "list_resolver" {
  api_id      = aws_appsync_graphql_api.orcabus_metadata.id
  type        = "Query"
  field       = local.list_query_name
  kind        = "UNIT"
  data_source = aws_appsync_datasource.rds_datasource.name
  code        = file(local.list_resolver_file_path)

  runtime {
    name            = "APPSYNC_JS"
    runtime_version = "1.0.0"
  }
}

# ------------------------------------------------------------------------------
# AppSync Custom Domain and DNS
# ------------------------------------------------------------------------------

resource "aws_appsync_domain_name" "appsync_domain_name" {
  domain_name     = local.lims_domain
  certificate_arn = aws_acm_certificate.lims_vault_acm.arn
}

resource "aws_appsync_domain_name_api_association" "appsync_domain_name_association" {
  api_id      = aws_appsync_graphql_api.orcabus_metadata.id
  domain_name = aws_appsync_domain_name.appsync_domain_name.domain_name
}

resource "aws_route53_record" "appsync_domain_name_record" {
  zone_id = data.aws_ssm_parameter.hosted_zone_id.value
  name    = local.lims_domain
  type    = "CNAME"
  ttl     = 300
  records = [aws_appsync_domain_name.appsync_domain_name.appsync_domain_name]
}
