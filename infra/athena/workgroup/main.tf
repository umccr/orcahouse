terraform {
  required_version = ">= 1.15.0"

  backend "s3" {
    bucket       = "terraform-states-ccfgcm"
    key          = "115253169271/orcahouse/athena/workgroup/terraform.tfstate"
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
  namespace = "orcahouse"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_s3_bucket" "dev_cache" {
  bucket = "${local.namespace}-dev-cache-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}-an"
}

data "aws_s3_bucket" "prod_cache" {
  bucket = "${local.namespace}-prod-cache-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}-an"
}
