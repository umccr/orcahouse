terraform {
  required_version = ">= 1.15.0"

  backend "s3" {
    bucket       = "terraform-states-ccfgcm"
    key          = "115253169271/orcahouse/redshift/environments/dev/terraform.tfstate"
    region       = "ap-southeast-2"
    use_lockfile = true
    encrypt      = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.45.0"
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
  namespace   = "orcahouse"
  environment = "dev"
  db_name     = "orcavault"
}

data "aws_caller_identity" "current" {}

data "aws_vpc" "primary" {
  tags = {
    Name = "UomPrimaryVpc"
  }
}

data "aws_subnets" "uom_private_subnets_ids" {
  filter {
    name   = "tag:Network"
    values = ["Private"]
  }
}

data "aws_security_group" "uom_primary_sg" {
  filter {
    name   = "tag:Name"
    values = ["UomPrimaryVpcEndpoints"]
  }
}

# ---

module "redshift_serverless" {
  source = "../../modules/redshift-serverless"

  namespace_name       = "${local.namespace}-${local.environment}"
  workgroup_name       = "${local.namespace}-${local.environment}"
  db_name              = local.db_name
  base_capacity        = 4
  max_capacity         = 4
  environment          = local.environment
  subnet_ids           = data.aws_subnets.uom_private_subnets_ids.ids
  security_group_ids   = [data.aws_security_group.uom_primary_sg.id]
  compute_limit_amount = 60 # RPU consumed per hour
  data_limit_amount    = 1  # TB
}
