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
  name_prefix       = "orcavault-run-${var.environment}-publish"
  event_source      = "orcahouse.orcavault"
  event_detail_type = "OrcaVaultPublishFinished"

  # The stage does nothing of its own yet, so it only ends succeeded or error.
  outcomes           = ["succeeded", "error"]
  succeeded_outcomes = ["succeeded"]
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

module "finish" {
  source = "../sfn-finish"

  environment        = var.environment
  event_source       = local.event_source
  event_detail_type  = local.event_detail_type
  succeeded_outcomes = local.succeeded_outcomes
}
