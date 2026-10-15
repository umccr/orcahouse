# The entrypoint for the module.

terraform {
  required_version = ">= 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.45.0"
    }
  }
}

locals {
  name_prefix          = "orcavault-run-${var.environment}"
  container_name       = "dbt"
  results_prefix       = "runs/"
  event_source         = "orcahouse.orcavault"
  event_detail_type    = "OrcaVaultRunFinished"
  region               = data.aws_region.current.region
  console_url          = "https://${local.region}.console.aws.amazon.com"
  execution_url_prefix = "${local.console_url}/states/home?region=${local.region}#/v2/executions/details/"

  # The console escapes names twice using $ in place of %.
  log_group_name    = replace(urlencode(urlencode(aws_cloudwatch_log_group.dbt.name)), "%", "$")
  log_stream_prefix = replace(urlencode(urlencode("${local.container_name}/${local.container_name}/")), "%", "$")
  logs_url_prefix   = "${local.console_url}/cloudwatch/home?region=${local.region}#logsV2:log-groups/log-group/${local.log_group_name}/log-events/${local.log_stream_prefix}"
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

data "aws_ecr_repository" "dbt" {
  name = var.ecr_repository_name
}
