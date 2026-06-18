terraform {
  required_version = ">= 1.15.0"

  backend "s3" {
    bucket       = "terraform-states-ccfgcm"
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

# ---

module "lakeformation_source_oncomart" {
  source = "../../modules/lakeformation-source"

  dw_account_id = data.aws_caller_identity.current.id
  database_name = "oncovault_dev_mart"

  tables = {

    purple_qc = {
      excluded_columns = []
      included_columns = []
      data_filters = {
        filter_qc_status = {
          row_filter_expression = "qc_status != 'DELETED'"
        }
      }
    }

    amber_qc = {
      excluded_columns = []
      included_columns = []
      data_filters = {
        filter_qc_status = {
          row_filter_expression = "qc_status != 'DELETED'"
        }
      }
    }

  }

  consumer_account_ids = [
    "472057503814",
  ]

  # TODO implement Data Cell Filter - see aws_lakeformation_data_cells_filter in modules/lakeformation-source/main.tf
  #  typically, the table get (pre) filtered before sharing via RAM

}
