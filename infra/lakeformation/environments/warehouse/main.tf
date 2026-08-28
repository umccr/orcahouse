terraform {
  required_version = ">= 1.15.0"

  backend "s3" {
    bucket       = "terraform-states-363226301494-ap-southeast-2-an"
    key          = "115253169271/orcahouse/lakeformation/environments/warehouse/terraform.tfstate"
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

data "aws_region" "current" {}

# ---

# FIXME TODO - tuning up in the progress for cross-account sharing

# module "lakeformation_source_oncomart" {
#   source = "../../modules/lakeformation-source"
#
#   dw_account_id = data.aws_caller_identity.current.id
#   database_name = "oncovault_dev_mart"
#
#   tables = {
#
#     purple_qc = {
#       data_filters = {
#         filter_purple_qc_column = {
#           row_filter_expression = null
#           included_columns      = []
#           # FIXME still experimenting -
#           #  we could as well pre-built the mart table with excluded columns
#           #  then the LF permission setup become straight forward table sharing
#           excluded_columns = [
#             "gender_amber",
#             "gender_cobalt"
#           ]
#         }
#       }
#     }
#
#     amber_qc = {
#       data_filters = {
#         filter_qc_status = {
#           row_filter_expression = "qc_status != 'DELETED'"
#         }
#       }
#     }
#
#   }
#
#   consumer_accounts = {
#     "472057503814" = {
#       principal_arns = [
#         local.sso_admin_role_arn,
#         local.sso_prod_exp_role_arn,
#         local.sso_prod_ops_role_arn,
#       ]
#     }
#   }
#
#   # FIXME still experimenting - this is POC mart built out of oncovault warehouse
#   #  the plan is to make a dedicate mart setup rather than shoehorning within oncovault
#   data_bucket_names = [
#     "oncovault-dev-warehouse-115253169271-ap-southeast-2-an"
#   ]
#
# }
