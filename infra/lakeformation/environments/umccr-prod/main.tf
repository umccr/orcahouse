terraform {
  required_version = ">= 1.15.0"

  backend "s3" {
    # FIXME update this when the prod account has migrated to unimelb tenancy
    # bucket       = "terraform-states-363226301494-ap-southeast-2-an"
    # key          = "115253169271/orcahouse/lakeformation/environments/umccr-prod/terraform.tfstate"
    bucket       = "umccr-terraform-states"
    key          = "orcahouse-lakeformation/environments/umccr-prod/terraform.tfstate"
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

data "aws_caller_identity" "current" {}

module "lakeformation_consumer" {
  source = "../../modules/lakeformation-consumer"

  dw_account_id = "115253169271"

  database_resource_links = {
    "mart"   = "orcavault_dev_mart"
    "result" = "oncovault_dev_mart"
  }
}
