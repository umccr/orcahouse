terraform {
  required_version = ">= 1.10.0"

  backend "s3" {
    bucket         = "umccr-terraform-states"
    key            = "orcahouse-event-ingestion/terraform.tfstate"
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

provider "aws" {
  region = "ap-southeast-2"
  default_tags {
    tags = {
      "umccr-org:Product" = "OrcaHouse"
      "umccr-org:Creator" = "Terraform"
      "umccr-org:Service" = "EventIngestion"
    }
  }
}

locals {
  # warehouse_name = "orcahouse"
  # rds_security_group_id = "sg-069849c9157d4fb66"
  python_version = "3.13"
  # orcabus_bus_name = "OrcaBusMain"
  iam_path = "/orcavault/serviceingestion/"
  # orcahouse_db_sg_id = {
  #   dev  = ""
  #   prod = "sg-013b6e66086adc6a6"
  #   stg  = ""
  # }
}

module "common" {
  source = "../common/config"
}

################################################################################
# VPC / Networking

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [module.common.main_vpc_id]
  }
  
  tags = {
    Tier = "private"
  }
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
  name = "db_secret_access"
  path = local.iam_path
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


# IAM Policy allowing Lambda to create Network Interfaces
# (required for Lambda deployment in VPC)
# https://docs.aws.amazon.com/lambda/latest/dg/configuration-vpc.html#configuration-vpc-permissions
data "aws_iam_policy" "lambda_vpc_access" {
  name = "AWSLambdaVPCAccessExecutionRole"
}


################################################################################
# Lambda Layer for psycopg2 (postgres DB adapter for Python)

# Install psycopg2 binary in a temporary directory
resource "null_resource" "install_psycopg2" {
  # Trigger for new python versions only
  triggers = {
    # Trigger on python version changes
    python = local.python_version
    # Trigger every time
    # time   = timestamp()
    # Trigger on changes to sha1 of the directory of the layer package
    # dir_sha1 = sha1(join("", [for f in fileset(".temp/lambda-layer/python", "*"): filesha1(".temp/lambda-layer/${f}")]))
  }

  provisioner "local-exec" {
    command = "pip3 install --platform manylinux2014_x86_64 --target .temp/lambda-layer/python --python-version ${local.python_version} --only-binary=:all: psycopg2-binary"
  }
}

# Create package for Lambda layer (psycopg2)
data "archive_file" "lambda_layer" {
  type        = "zip"
  source_dir  = ".temp/lambda-layer"
  output_path = ".temp/output/layer.zip"

  depends_on = [
    null_resource.install_psycopg2
  ]
}

# Manage Lambda layer
resource "aws_lambda_layer_version" "psycopg2_layer" {
  filename            = data.archive_file.lambda_layer.output_path
  layer_name          = "psycopg2-layer"
  compatible_runtimes = ["python${local.python_version}"]
  description         = "Layer containing psycopg2 library"

  source_code_hash = data.archive_file.lambda_layer.output_base64sha256
}



