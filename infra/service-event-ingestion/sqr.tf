
################################################################################
# Lambda for Sequence Run Manager event handling

# SQR Lambda Role
resource "aws_iam_role" "sqr_lambda_role" {
  name = "sqr_lambda_role"
  path = local.iam_path

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

# Attach the policy to the Lambda role
resource "aws_iam_role_policy_attachment" "secrets_policy_attachment" {
  role       = aws_iam_role.sqr_lambda_role.name
  policy_arn = aws_iam_policy.db_secret_access.arn
}
# Attach VPC access policy
resource "aws_iam_role_policy_attachment" "sqr_lambda_vpc_access" {
  role       = aws_iam_role.sqr_lambda_role.name
  policy_arn = data.aws_iam_policy.lambda_vpc_access.arn
}
# Attach VPC access policy restriction
# https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html#configuration-vpc-best-practice
resource "aws_iam_policy" "sqr_lambda_vpc_access_restriction" {
  name = "SqrLambdaVpcAccessRestriction"
  path = local.iam_path

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
              aws_lambda_function.sqr_event_handler.arn
            ]
          }
        }
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "sqr_lambda_vpc_access_restriction" {
  role       = aws_iam_role.sqr_lambda_role.name
  policy_arn = aws_iam_policy.sqr_lambda_vpc_access_restriction.arn
}

# Create package for Lambda function
data "archive_file" "lambda_package" {
  type        = "zip"
  source_dir  = "lambda/sqr_event_handler"
  output_path = ".temp/lambda/sqr_event_handler.zip"

  excludes = [
    "__pycache__",
    "*.pyc",
    "*.pyo",
    "*.pyd"
  ]
}

# SQR Lambda function resource
resource "aws_lambda_function" "sqr_event_handler" {
  filename      = data.archive_file.lambda_package.output_path
  function_name = "sqr_event_handler"
  role          = aws_iam_role.sqr_lambda_role.arn
  handler       = "sqr_event_handler.handler" # Assuming your main file is handler.py
  runtime       = "python3.13"
  timeout       = 30
  memory_size   = 128

  layers = [aws_lambda_layer_version.psycopg2_layer.arn]

  source_code_hash = data.archive_file.lambda_package.output_base64sha256

  vpc_config {
    subnet_ids         = data.aws_subnets.private.ids
    security_group_ids = [local.rds_security_group_id]
  }

  environment {
    variables = {
      DB_SECRET_NAME = data.aws_secretsmanager_secret.db_secret.name
    }
  }
}


################################################################################
# TODO: add EventBridge rules to trigger Lambda function


resource "aws_cloudwatch_event_rule" "sqr_event_ingestion" {
  name        = "sqr_event_ingestion"
  description = "Forward SQR events to an ingestion Lambda for ingestion into the OrcaHouse Vault"

  event_bus_name = local.orcabus_bus_name

  event_pattern = jsonencode({
    detail-type = [
      "SequenceRunStateChange"
    ],
    source = [
      "orcabus.sequencerunmanager"
    ]
  })
}

resource "aws_cloudwatch_event_target" "sqr_lambda" {
  target_id = "SendToSQRLambda"
  event_bus_name = local.orcabus_bus_name
  rule      = aws_cloudwatch_event_rule.sqr_event_ingestion.name
  arn       = aws_lambda_function.sqr_event_handler.arn

  depends_on = [ aws_lambda_function.sqr_event_handler, aws_cloudwatch_event_rule.sqr_event_ingestion ]
}

resource "aws_lambda_permission" "sqr_event_allow_invoke" {
  statement_id  = "AllowExecutionFromEventBridgeRule"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sqr_event_handler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.sqr_event_ingestion.arn
  #   qualifier     = aws_lambda_alias.test_alias.name
}
