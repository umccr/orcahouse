terraform {
  required_version = ">= 1.15.0"

  backend "s3" {
    bucket       = "terraform-states-363226301494-ap-southeast-2-an"
    key          = "115253169271/orcahouse/ecs/orcavault-run/environments/dev/terraform.tfstate"
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

  allowed_account_ids = ["115253169271"]

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
  environment = "dev"
}

variable "orcavault_release_ref" {
  description = "The orcavault tag or commit to run. Its image must already be pushed, see the README."
  type        = string
}

variable "schedule_enabled" {
  description = "Set to false to pause the daily run without removing anything."
  type        = bool
  default     = true
}

# ---

module "orcavault_run" {
  source = "../../modules/orcavault-run"

  environment             = local.environment
  redshift_workgroup_name = "orcahouse-${local.environment}"
  orcavault_release_ref   = var.orcavault_release_ref
  schedule_enabled        = var.schedule_enabled
}

output "state_machine_arn" {
  description = "The dev OrcaVault run state machine."
  value       = module.orcavault_run.state_machine_arn
}

output "start_run_command" {
  description = "Start a full dev run now. See the README for other requests."
  value       = module.orcavault_run.start_run_command
}

output "results_bucket" {
  description = "Each dev run's event, at runs/<execution name>/event.json."
  value       = module.orcavault_run.results_bucket
}

output "debug_command" {
  description = "Run dbt debug in the dev task, to check it can reach Redshift."
  value       = module.orcavault_run.debug_command
}

output "logs_command" {
  description = "Follow the dev dbt logs."
  value       = module.orcavault_run.logs_command
}

output "dbt_task_db_identity" {
  description = "Redshift database user the dev dbt task connects as. See the README for its grants."
  value       = module.orcavault_run.dbt_task_db_identity
}

output "alerts_topic_arn" {
  description = "SNS topic receiving dev run alerts. Subscribe to it after applying."
  value       = module.orcavault_run.alerts_topic_arn
}
