terraform {
  required_version = ">= 1.10.0"

  backend "s3" {
    bucket         = "umccr-terraform-states"
    key            = "orcahouse-aurora-su/terraform.tfstate"
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
      "umccr-org:Service" = "OrcaHouse"
      "umccr-org:Source"  = "https://github.com/umccr/orcahouse"
    }
  }
}

locals {
  stack_name = "orcahouse"

  sorted_private_subnets = sort(data.aws_subnets.private_subnets_ids.ids)

  selected_private_subnet_id = local.sorted_private_subnets[0]

  orcahouse_db_sg_id = {
    dev  = ""
    prod = "sg-013b6e66086adc6a6"
    stg  = ""
  }
}

data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_vpc" "main_vpc" {
  # Using tags filter on networking stack to get main-vpc
  tags = {
    Name        = "main-vpc"
    Stack       = "networking"
    Environment = terraform.workspace
  }
}

data "aws_subnets" "database_subnets_ids" {
  filter {
    name = "vpc-id"
    values = [data.aws_vpc.main_vpc.id]
  }

  tags = {
    Tier = "database"
  }
}

data "aws_subnets" "private_subnets_ids" {
  filter {
    name = "vpc-id"
    values = [data.aws_vpc.main_vpc.id]
  }

  tags = {
    Tier = "private"
  }
}

data "aws_subnet" "selected" {
  id = local.selected_private_subnet_id
}

data "aws_rds_cluster" "orcahouse_db" {
  cluster_identifier = "orcahouse-db"
}

data "aws_secretsmanager_random_password" "this" {
  password_length    = 50
  exclude_characters = "\"#$%&'()*+,-./:;<=>?[\\]^_`{|}~."
}

data "aws_serverlessapplicationrepository_application" "this" {
  # We leverage SAM serverless repo CloudFormation stack for secret rotation.
  # These rotation Lambda templates are developed, maintained and provided by AWS.
  # https://docs.aws.amazon.com/secretsmanager/latest/userguide/reference_available-rotation-templates.html
  # https://serverlessrepo.aws.amazon.com/applications/us-east-1/297356227824/SecretsManagerRDSPostgreSQLRotationSingleUser
  application_id = "arn:aws:serverlessrepo:us-east-1:297356227824:applications/SecretsManagerRDSPostgreSQLRotationSingleUser"
}
