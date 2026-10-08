terraform {
  required_version = ">= 1.15.0"

  backend "s3" {
    bucket       = "terraform-states-363226301494-ap-southeast-2-an"
    key          = "115253169271/orcahouse/ecs/orcavault-run/terraform.tfstate"
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

# ---

locals {
  name_prefix    = "orcavault-run"
  container_name = "dbt"

  # Where the runner writes each run's event in the results bucket. The
  # runner has the same prefix, see docker/runner/orcavault_runner/__main__.py.
  results_prefix = "runs/"

  # The event each run ends with, see the README.
  event_source      = "orcahouse.orcavault"
  event_detail_type = "OrcaVault Run Finished"

  execution_url_prefix = "https://${data.aws_region.current.region}.console.aws.amazon.com/states/home?region=${data.aws_region.current.region}#/v2/executions/details/"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

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

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }
}

# The same group the Redshift workgroup uses, so the task can reach it on 5439.
data "aws_security_group" "uom_primary_sg" {
  vpc_id = data.aws_vpc.primary.id

  filter {
    name   = "tag:Name"
    values = ["UomPrimaryVpcEndpoints"]
  }
}

data "aws_redshiftserverless_workgroup" "this" {
  workgroup_name = var.redshift_workgroup_name
}

data "aws_s3_bucket" "cdc" {
  bucket = var.cdc_bucket_name
}
