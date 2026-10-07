terraform {
  required_version = ">= 1.10.0"

  backend "s3" {
    bucket         = "umccr-terraform-states"
    key            = "orcahouse-ecs/orcavault-dbt/terraform.tfstate"
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
  stack_name    = "orcahouse"
  database_name = "orcavault"

  orcahouse_db_sg_id = {
    dev  = ""
    prod = "sg-013b6e66086adc6a6"
    stg  = ""
  }
}

data "aws_region" "current" {}

data "aws_vpc" "main_vpc" {
  # Using tags filter on networking stack to get main-vpc
  tags = {
    Name        = "main-vpc"
    Stack       = "networking"
    Environment = terraform.workspace
  }
}

data "aws_subnets" "private_subnets" {
  filter {
    name = "vpc-id"
    values = [data.aws_vpc.main_vpc.id]
  }

  tags = {
    Tier = "private"
  }
}

data "aws_rds_cluster" "orcahouse_db" {
  cluster_identifier = "orcahouse-db"
}

data "aws_ssm_parameter" "ro_username" {
  # For daily scheduled dbt run; we have to run post-ELT hook grant select
  # to Athena db ro user for mart schema. We pass this ro username via ECS
  # task definition env var at terraform deploy time.
  # See orcavault/macros/grant_select.sql
  name = "/${local.stack_name}/${local.database_name}/athena_username"
}
