provider "aws" {
  alias = "umccr"

  region  = "ap-southeast-2"
  profile = "umccr-prod-admin"

  default_tags {
    tags = {
      "umccr-org:Product" = "OrcaHouse"
      "umccr-org:Creator" = "Terraform"
      "umccr-org:Service" = "OrcaHouse"
      "umccr-org:Source"  = "https://github.com/umccr/orcahouse"
    }
  }
}

# FIXME still experimenting - this has moved into the warehouse source side as pre-filtered data cell share table

data "aws_iam_roles" "sso_admin" {
  provider = aws.umccr

  name_regex  = "AWSReservedSSO_AdministratorAccess_.*"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}

data "aws_iam_roles" "sso_prod_ops" {
  provider = aws.umccr

  name_regex  = "AWSReservedSSO_ProdOperator_.*"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}

data "aws_iam_roles" "sso_prod_exp" {
  provider = aws.umccr

  name_regex  = "AWSReservedSSO_ProdDataExplorer_.*"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}

locals {
  sso_admin_role_arn    = tolist(data.aws_iam_roles.sso_admin.arns)[0]
  sso_prod_ops_role_arn = tolist(data.aws_iam_roles.sso_prod_ops.arns)[0]
  sso_prod_exp_role_arn = tolist(data.aws_iam_roles.sso_prod_exp.arns)[0]
}
