terraform {
  required_version = ">= 1.15.0"

  backend "s3" {
    # FIXME update this when the prod account has migrated to unimelb tenancy
    # bucket       = "terraform-states-ccfgcm"
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

data "aws_iam_roles" "sso_admin" {
  name_regex  = "AWSReservedSSO_AdministratorAccess_.*"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}

data "aws_iam_roles" "sso_prod_ops" {
  name_regex  = "AWSReservedSSO_ProdOperator_.*"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}

data "aws_iam_roles" "sso_prod_exp" {
  name_regex  = "AWSReservedSSO_ProdDataExplorer_.*"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}

locals {
  sso_admin_role_arn    = tolist(data.aws_iam_roles.sso_admin.arns)[0]
  sso_prod_ops_role_arn = tolist(data.aws_iam_roles.sso_prod_ops.arns)[0]
  sso_prod_exp_role_arn = tolist(data.aws_iam_roles.sso_prod_exp.arns)[0]
}

# ---

module "lakeformation_consumer_oncomart" {
  source = "../../modules/lakeformation-consumer"

  dw_account_id    = "115253169271"
  dw_database_name = "oncovault_dev_mart"

  this_account_id            = data.aws_caller_identity.current.id
  this_account_database_name = "mart"

  principal_grants = {

    (local.sso_admin_role_arn) = {
      tables      = []
      permissions = ["SELECT", "DESCRIBE"]
    },

    (local.sso_prod_ops_role_arn) = {
      tables = [
        "purple_qc",
        "amber_qc",
      ]
      permissions = ["SELECT", "DESCRIBE"]
    },

    (local.sso_prod_exp_role_arn) = {
      tables = [
        "purple_qc",
        "amber_qc",
      ]
      permissions = ["SELECT", "DESCRIBE"]
    },

  }
}
