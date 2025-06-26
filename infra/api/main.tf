terraform {
  required_version = ">= 1.10.0"

  backend "s3" {
    bucket         = "umccr-terraform-states"
    key            = "orcahouse/api/terraform.tfstate"
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

# provider "aws" {
#   alias  = "use1" # US-East-1
#   region = "us-east-1"

#   default_tags {
#     tags = {
#       "umccr-org:Product" = "OrcaHouse"
#       "umccr-org:Creator" = "Terraform"
#       "umccr-org:Service" = "OrcaHouse"
#       "umccr-org:Source"  = "https://github.com/umccr/orcahouse"
#     }
#   }
# }


# ------------------------------------------------------------------------------
# Data Sources
# ------------------------------------------------------------------------------

data "aws_ssm_parameter" "cognito_user_pool_id" {
  name = "/data_portal/client/cog_user_pool_id"
}

data "aws_ssm_parameter" "orcaui_cognito_app_client_id" {
  name = "/orcaui/cog_app_client_id_stage"
}

data "aws_ssm_parameter" "hosted_zone_id" {
  name = "/hosted_zone/umccr/id"
}

data "aws_ssm_parameter" "acm_cert_arn" {
  name = "cert_apse2_arn"
}

data "aws_vpc" "main_vpc" {
  # Using tags filter on networking stack to get main-vpc
  tags = {
    Name        = "main-vpc"
    Stack       = "networking"
    Environment = terraform.workspace
  }
}

data "aws_subnets" "private_subnets_ids" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main_vpc.id]
  }

  tags = {
    Tier = "private"
  }
}


# ------------------------------------------------------------------------------
# Variables
# ------------------------------------------------------------------------------

variable "db_name" {
  description = "The database name from the RDS cluster"
  type        = string
}

# ------------------------------------------------------------------------------
# Locals
# ------------------------------------------------------------------------------

locals {
  stack_name  = "orcahouse"
  mart_domain = "mart.prod.umccr.org"

  rds_secret_arn = "arn:aws:secretsmanager:ap-southeast-2:472057503814:secret:orcahouse/dbuser_ro-bT5oGK" # pragma: allowlist secret
  # rds_secret_arn = "arn:aws:secretsmanager:ap-southeast-2:843407916570:secret:orcabus/master-rds-Fne1fB" # pragma: allowlist secret
  function_name = "orcahouse-api-${var.db_name}"

  orcahouse_db_sg_id = {
    dev  = "sg-03abb47eba799e044"
    prod = "sg-013b6e66086adc6a6"
    stg  = ""
  }
}



# ------------------------------------------------------------------------------
# Lambda for API server
# ------------------------------------------------------------------------------

resource "aws_lambda_function" "api" {
  filename      = "${path.module}/lambda-server/dist/index.zip"
  function_name = local.function_name
  role          = aws_iam_role.api_lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs22.x"
  architectures = ["arm64"]
  memory_size   = 2048
  timeout       = 29

  source_code_hash = filebase64sha256("${path.module}/lambda-server/dist/index.zip")

  layers = [
    "arn:aws:lambda:ap-southeast-2:665172237481:layer:AWS-Parameters-and-Secrets-Lambda-Extension-Arm64:17"
  ]

  vpc_config {
    subnet_ids         = sort(data.aws_subnets.private_subnets_ids.ids)
    security_group_ids = [local.orcahouse_db_sg_id[terraform.workspace]]
  }

  environment {
    variables = {
      DATABASE_NAME = var.db_name
      GRAPHILE_ENV  = "production"
      SECRET_ARN    = local.rds_secret_arn
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_vpc_access_execution,
    aws_iam_role_policy_attachment.lambda_secret_access,

    aws_cloudwatch_log_group.lambda_api
  ]
}

resource "aws_cloudwatch_log_group" "lambda_api" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = 365

}

resource "aws_iam_role" "api_lambda_role" {
  name = "${local.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.api_lambda_role.name
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_access_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  role       = aws_iam_role.api_lambda_role.name
}

resource "aws_iam_policy" "db_secret_access" {
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = ["${local.rds_secret_arn}"]
      }
    ]
  })

}


resource "aws_iam_role_policy_attachment" "lambda_secret_access" {
  role       = aws_iam_role.api_lambda_role.name
  policy_arn = aws_iam_policy.db_secret_access.arn
}


# ------------------------------------------------------------------------------
# HTTP API Gateway
# ------------------------------------------------------------------------------


resource "aws_apigatewayv2_api" "http_api" {
  name          = "orcahouse-${var.db_name}"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_authorizer" "data_portal" {
  api_id           = aws_apigatewayv2_api.http_api.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "PortalAuthorizer"

  jwt_configuration {
    audience = [data.aws_ssm_parameter.orcaui_cognito_app_client_id.value]
    issuer   = "https://cognito-idp.ap-southeast-2.amazonaws.com/${data.aws_ssm_parameter.cognito_user_pool_id.value}"
  }
}

resource "aws_apigatewayv2_integration" "lambda_server_integration" {
  api_id           = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.api.invoke_arn
}

resource "aws_apigatewayv2_route" "get_handler" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /{PROXY+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_server_integration.id}"
}

resource "aws_apigatewayv2_route" "post_handler" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /{PROXY+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_server_integration.id}"

  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.data_portal.id

}

resource "aws_apigatewayv2_stage" "mart" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.http_api.execution_arn}/*"
}


# ------------------------------------------------------------------------------
# HTTP API Gateway
# ------------------------------------------------------------------------------

resource "aws_apigatewayv2_domain_name" "mart_domain_name" {
  domain_name = local.mart_domain

  domain_name_configuration {
    certificate_arn = data.aws_ssm_parameter.acm_cert_arn.value
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
}

resource "aws_apigatewayv2_api_mapping" "example" {
  api_id      = aws_apigatewayv2_api.http_api.id
  domain_name = aws_apigatewayv2_domain_name.mart_domain_name.domain_name
  stage       = aws_apigatewayv2_stage.mart.id
}

resource "aws_route53_record" "mart_domain_record" {
  zone_id = data.aws_ssm_parameter.hosted_zone_id.value
  name    = local.mart_domain
  type    = "A"
  
  alias {
    name                   = aws_apigatewayv2_domain_name.mart_domain_name.domain_name_configuration[0].target_domain_name
    zone_id                = aws_apigatewayv2_domain_name.mart_domain_name.domain_name_configuration[0].hosted_zone_id
    evaluate_target_health = false
  }

}
