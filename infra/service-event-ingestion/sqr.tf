
################################################################################
# Lambda for Sequence Run Manager event handling

# SQR Lambda Role
resource "aws_iam_role" "sqr_lambda_role" {
  name = "sqr_lambda_role"

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

# Manage Lambda function resource
resource "aws_lambda_function" "postgres_lambda" {
  filename      = data.archive_file.lambda_package.output_path
  function_name = "sqr_event_handler"
  role          = aws_iam_role.sqr_lambda_role.arn
  handler       = "sqr_event_handler.handler"  # Assuming your main file is handler.py
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

