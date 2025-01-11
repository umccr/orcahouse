terraform {
  required_version = ">= 1.10.0"

  backend "s3" {
    bucket         = "umccr-terraform-states"
    key            = "orcahouse-glue/terraform.tfstate"
    region         = "ap-southeast-2"
    dynamodb_table = "terraform-state-lock"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.78.0"
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
  stack_name                 = "orcahouse"
  sorted_private_subnets     = sort(data.aws_subnets.private_subnets_ids.ids)
  selected_private_subnet_id = local.sorted_private_subnets[0]
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

variable "orcabus_compute_sg_id" {
  default = {
    dev  = ""
    prod = "sg-02e363a39220c955f"
    stg  = ""
  }
}

variable "staging_bucket" {
  default = {
    dev  = ""
    prod = "orcahouse-staging-data-472057503814"
    stg  = ""
  }
}

data "aws_s3_bucket" "glue_script_bucket" {
  bucket = var.staging_bucket[terraform.workspace]
}
