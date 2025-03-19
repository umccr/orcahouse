# !!! EXPERIMENTAL NOT IN USE YET !!!

terraform {
  required_version = ">= 1.10.0"

  # backend "s3" {
  #   bucket         = "umccr-terraform-states"
  #   key            = "orcahouse-redshift/terraform.tfstate"
  #   region         = "ap-southeast-2"
  #   dynamodb_table = "terraform-state-lock"
  # }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.91.0"
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
    }
  }
}

locals {
  warehouse_name = "orcahouse"

  portal_rds_security_group_id = {
    dev  = "sg-088c09bfd006061d4"
    prod = "sg-00fdf25d4299d1451"
    stg  = "sg-073f88354461d83b3"
  }

  orcabus_rds_security_group_id = {
    dev  = "sg-03cbdd2371989f2ec"
    prod = "sg-072af16b1e4af3b4f"
    stg  = "sg-0819e9926b6c4c0a0"
  }
}

# ---

data "aws_vpc" "main_vpc" {
  tags = {
    Name  = "main-vpc"
    Stack = "networking"
  }
}

data "aws_subnets" "database" {
  filter {
    name = "vpc-id"
    values = [data.aws_vpc.main_vpc.id]
  }

  tags = {
    Tier = "database"
  }
}

# ---

resource "aws_redshiftserverless_namespace" "this" {
  namespace_name        = local.warehouse_name
  manage_admin_password = true
}

resource "aws_redshiftserverless_workgroup" "this" {
  workgroup_name       = local.warehouse_name
  namespace_name       = aws_redshiftserverless_namespace.this.namespace_name
  base_capacity        = 8
  max_capacity         = 8
  publicly_accessible  = false
  enhanced_vpc_routing = true
  subnet_ids           = data.aws_subnets.database.ids

  security_group_ids = [
    local.portal_rds_security_group_id[terraform.workspace],
    local.orcabus_rds_security_group_id[terraform.workspace],
  ]

  config_parameter {
    parameter_key   = "auto_mv"
    parameter_value = "true"
  }
  config_parameter {
    parameter_key   = "datestyle"
    parameter_value = "ISO, MDY"
  }
  config_parameter {
    parameter_key   = "enable_case_sensitive_identifier"
    parameter_value = "true"
  }
  config_parameter {
    parameter_key   = "enable_user_activity_logging"
    parameter_value = "true"
  }
  config_parameter {
    parameter_key   = "max_query_execution_time"
    parameter_value = "300"  # seconds
  }
  config_parameter {
    parameter_key   = "query_group"
    parameter_value = "default"
  }
  config_parameter {
    parameter_key   = "require_ssl"
    parameter_value = "true"
  }
  config_parameter {
    parameter_key   = "search_path"
    parameter_value = "$user, public"
  }
  config_parameter {
    parameter_key   = "use_fips_ssl"
    parameter_value = "true"
  }
}

resource "aws_redshiftserverless_usage_limit" "compute_limit" {
  resource_arn  = aws_redshiftserverless_workgroup.this.arn
  usage_type    = "serverless-compute"
  amount        = 60
  period        = "monthly"
  breach_action = "deactivate"
}

resource "aws_redshiftserverless_usage_limit" "data_limit" {
  resource_arn  = aws_redshiftserverless_workgroup.this.arn
  usage_type    = "cross-region-datasharing"
  amount        = 1
  period        = "monthly"
  breach_action = "deactivate"
}
