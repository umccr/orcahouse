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

module "finish" {
  source = "../sfn-finish"

  environment        = var.environment
  event_source       = local.event_source
  event_detail_type  = local.event_detail_type
  succeeded_outcomes = local.succeeded_outcomes
}

# The state machine, its logs, its roles and its alarm. The stage is started by the run's
# event, so EventBridge rules start it rather than a schedule.
module "stage" {
  source = "../sfn-stage"

  environment     = var.environment
  name            = "publish"
  definition      = local.definition
  starter_service = "events.amazonaws.com"

  max_hours_without_success = var.max_hours_without_success
}
