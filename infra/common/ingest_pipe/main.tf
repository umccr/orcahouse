
module "common" {
  source = "../config"
}


################################################################################
# Secrets Manager for DB access credentials

# Reference existing Secrets Manager secret
data "aws_secretsmanager_secret" "db_secret" {
  name = var.db_secret_name
}

data "aws_secretsmanager_secret_version" "db_secret_current" {
  secret_id = data.aws_secretsmanager_secret.db_secret.id
}

# IAM Policy allowing access to Secrets Manager secret
resource "aws_iam_policy" "db_secret_access" {
  name_prefix = "${var.service_id}_DbSecretAccess"
  path        = var.iam_path
  description = "Policy to allow access to the DB secret in Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [data.aws_secretsmanager_secret.db_secret.arn]
      }
    ]
  })
}


################################################################################
# Lambda for Sequence Run Manager event handling

# DLQ for ingest lambda
resource "aws_sqs_queue" "dlq" {
  name = "${var.lambda_function_name}_dlq"
}
resource "aws_iam_policy" "dlq" {
  name_prefix = "${var.lambda_function_name}_DLQAccess"
  path        = var.iam_path
  description = "Policy to allow ingest lambda to send messages to its DLQ"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = [aws_sqs_queue.dlq.arn]
      }
    ]
  })
}


# Create the actual Lambda function using a 3rd party module
module "ingest_lambda" {
  source = "terraform-aws-modules/lambda/aws"

  function_name = var.lambda_function_name
  handler       = var.lambda_function_handler
  runtime       = "python3.13"
  publish       = true

  source_path = var.lambda_source_paths

  layers = var.lambda_layers

  environment_variables = {
    DB_SECRET_NAME = data.aws_secretsmanager_secret.db_secret.name
  }

  dead_letter_target_arn = aws_sqs_queue.dlq.arn

  vpc_subnet_ids         = module.common.main_vpc_private_subnet_ids
  vpc_security_group_ids = [module.common.orcahouse_db_sg_id[terraform.workspace]]
  attach_network_policy  = true

  cloudwatch_logs_retention_in_days = var.cloudwatch_logs_retention_in_days

}

# Ingest Lambda Role
# resource "aws_iam_role" "ingest_lambda_role" {
#   name_prefix = "${var.service_id}_IngestLambdaRole"
#   path        = var.iam_path

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRole"
#         Effect = "Allow"
#         Principal = {
#           Service = "lambda.amazonaws.com"
#         }
#       }
#     ]
#   })
# }

# Attach a policy to the Lambda role for Secrets Manager access
resource "aws_iam_role_policy_attachment" "ingest_secrets_policy_attachment" {
  # role       = aws_iam_role.ingest_lambda_role.name
  role       = module.ingest_lambda.lambda_role_name
  policy_arn = aws_iam_policy.db_secret_access.arn
}

# Attach a policy to the Lambda role to allow messages to be send to the DLQ
resource "aws_iam_role_policy_attachment" "ingest_dlq_attachment" {
  role       = module.ingest_lambda.lambda_role_name
  policy_arn = aws_iam_policy.dlq.arn
}


# Attach VPC access policy 
# TODO: handled by the lambda module
# resource "aws_iam_role_policy_attachment" "ingest_lambda_vpc_access" {
#   role       = aws_iam_role.ingest_lambda_role.name
#   policy_arn = module.common.lambda_vpc_access_policy_arn
# }

# Attach VPC access policy restriction
# https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html#configuration-vpc-best-practice
resource "aws_iam_policy" "ingest_lambda_vpc_access_restriction" {
  name_prefix = "${var.service_id}_IngestLambdaVpcAccessRestriction"
  path        = var.iam_path

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        "Effect" : "Deny",
        "Action" : [
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSubnets",
          "ec2:DetachNetworkInterface",
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses"
        ],
        "Resource" : ["*"],
        "Condition" : {
          "ArnEquals" : {
            "lambda:SourceFunctionArn" : [
              # aws_lambda_function.ingest_event_handler.arn
              module.ingest_lambda.lambda_function_arn
            ]
          }
        }
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "ingest_lambda_vpc_access_restriction" {
  # role       = aws_iam_role.ingest_lambda_role.name
  role       = module.ingest_lambda.lambda_role_name
  policy_arn = aws_iam_policy.ingest_lambda_vpc_access_restriction.arn
}

# Create package for Lambda function
# data "archive_file" "ingest_lambda_package" {
#   type        = "zip"
#   source_dir  = var.lambda_source_dir
#   output_path = var.lambda_artefact_out_path

#   excludes = [
#     "__pycache__",
#     "*.pyc",
#     "*.pyo",
#     "*.pyd"
#   ]
# }

# Ingest Lambda function resource
# resource "aws_lambda_function" "ingest_event_handler" {
#   filename      = data.archive_file.ingest_lambda_package.output_path
#   function_name = var.lambda_function_name
#   role          = aws_iam_role.ingest_lambda_role.arn
#   handler       = var.lambda_function_handler
#   runtime       = "python3.13"
#   timeout       = 30
#   memory_size   = 128

#   layers = var.lambda_layers

#   source_code_hash = data.archive_file.ingest_lambda_package.output_base64sha256

#   vpc_config {
#     subnet_ids         = module.common.main_vpc_private_subnet_ids
#     security_group_ids = [module.common.orcahouse_db_sg_id[terraform.workspace]]
#   }

#   environment {
#     variables = {
#       DB_SECRET_NAME = data.aws_secretsmanager_secret.db_secret.name
#     }
#   }
# }


################################################################################
# EventBridge rules to trigger Lambda function

resource "aws_cloudwatch_event_rule" "ingest_event_ingestion" {
  name_prefix = "${var.service_id}_IngestEventIngestion"
  description = "Forward Service events to an ingestion Lambda for ingestion into the OrcaHouse Vault"

  event_bus_name = module.common.orcabus_bus_name

  event_pattern = jsonencode(var.event_pattern)
}

resource "aws_cloudwatch_event_target" "ingest_lambda" {
  target_id      = "SendToIngestLambda"
  event_bus_name = module.common.orcabus_bus_name
  rule           = aws_cloudwatch_event_rule.ingest_event_ingestion.name
  # arn            = aws_lambda_function.ingest_event_handler.arn
  arn = module.ingest_lambda.lambda_function_arn

  # depends_on = [aws_lambda_function.ingest_event_handler, aws_cloudwatch_event_rule.ingest_event_ingestion]
  depends_on = [module.ingest_lambda, aws_cloudwatch_event_rule.ingest_event_ingestion]
}

resource "aws_lambda_permission" "ingest_event_allow_invoke" {
  statement_id = "AllowExecutionFromEventBridgeRule"
  action       = "lambda:InvokeFunction"
  # function_name = aws_lambda_function.ingest_event_handler.function_name
  function_name = module.ingest_lambda.lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ingest_event_ingestion.arn
}
