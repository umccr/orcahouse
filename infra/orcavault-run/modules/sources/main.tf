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
  name_prefix       = "orcavault-run-${var.environment}-sources"
  event_source      = "orcahouse.orcavault"
  event_detail_type = "OrcaVaultSourcesFinished"

  # degraded means some source is stale, which only delays its data because of the
  # orcavault watermark, so it doesn't fail the execution.
  outcomes           = ["succeeded", "degraded", "error"]
  succeeded_outcomes = ["succeeded", "degraded"]

  # OrcaGlue jobs opt in to this stage with this tag, see the OrcaGlue README_DEPLOY.md.
  glue_job_stage_tag   = { "orcahouse:pipeline-stage" = "sources" }
  glue_job_name_prefix = "orcaglue-${var.environment}-"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

module "crawl" {
  source = "../sfn-crawl"

  crawler_names    = var.cdc_crawler_names
  max_wait_minutes = var.crawl_max_wait_minutes
}

module "finish" {
  source = "../sfn-finish"

  environment        = var.environment
  event_source       = local.event_source
  event_detail_type  = local.event_detail_type
  succeeded_outcomes = local.succeeded_outcomes
}
