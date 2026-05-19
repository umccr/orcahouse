terraform {
  required_version = ">= 1.15.0"

  backend "s3" {
    bucket       = "terraform-states-ccfgcm"
    key          = "115253169271/orcahouse/dms/orcabus-db/terraform.tfstate"
    region       = "ap-southeast-2"
    use_lockfile = true
    encrypt      = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.43.0"
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

# ---

locals {
  name_prefix = "orcabus-db"
  databases   = ["workflow_manager", "sequence_run_manager", "metadata_manager", "filemanager"]
}

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

data "aws_secretsmanager_secret" "source" {
  name = "orcahouse/dms/orcabus-db"
}

data "aws_s3_bucket" "lz" {
  bucket = "orcahouse-landing-zone-115253169271-ap-southeast-2-an"
}
