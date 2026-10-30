# The dev environment deployment.

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
  description = "The orcavault tag or commit to deploy. The image must already be pushed."
  type        = string
}

variable "schedule_enabled" {
  description = "Set to false to pause the daily run."
  type        = bool
  default     = true
}

module "orcavault_run" {
  source = "../../modules/orcavault-run"

  environment             = local.environment
  redshift_workgroup_name = "orcahouse-${local.environment}"
  orcavault_release_ref   = var.orcavault_release_ref
  schedule_enabled        = var.schedule_enabled

  glue_databases = [
    "orcabus_case_manager",
    "orcabus_filemanager",
    "orcabus_metadata_manager",
    "orcabus_sequence_run_manager",
    "orcabus_workflow_manager",
    "data_portal",
  ]
  bucket_name = "orcahouse-prod-landing-zone-115253169271-ap-southeast-2-an"
  s3_prefix = [
    "orcabus/v1/cdc/",
    "data-portal/orcavault-legacy-20260623/orcavault/",
  ]
}

output "orcavault_run" {
  description = "The dev OrcaVault run outputs, see the module's outputs.tf."
  value       = module.orcavault_run
}
