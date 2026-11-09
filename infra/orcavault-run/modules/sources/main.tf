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
}

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

# The state machine, its logs, its roles and its alarm. Besides the crawlers, this stage
# only checks whether DMS is replicating.
module "stage" {
  source = "../sfn-stage"

  environment     = var.environment
  name            = "sources"
  definition      = local.definition
  starter_service = "scheduler.amazonaws.com"

  policy_statements = [{
    sid       = "CheckDmsTasks"
    actions   = ["dms:DescribeReplicationTasks"]
    resources = ["*"]
  }]

  source_policy_documents   = compact([module.crawl.policy_json])
  max_hours_without_success = var.max_hours_without_success
}
