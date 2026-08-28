# Login to Warehouse account and find the roles
# Console > AWS IAM > Roles

data "aws_iam_roles" "warehouse_sso_owner" {
  name_regex  = "AWSReservedSSO_PlatformOwnerAccess_.*"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}

data "aws_iam_roles" "warehouse_sso_admin" {
  name_regex  = "AWSReservedSSO_AWSAdministratorAccess_.*"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}

data "aws_iam_roles" "warehouse_sso_power_user" {
  name_regex  = "AWSReservedSSO_AWSPowerUserAccess_.*"
  path_prefix = "/aws-reserved/sso.amazonaws.com/"
}

data "aws_iam_role" "crawler" {
  # Created by infra/glue-crawler/orcabus-db/iam.tf
  name = "orcabus-db-glue-crawler-role"
}

data "aws_iam_role" "redshift_dev" {
  # Created by infra/redshift/modules/redshift-serverless/iam.tf
  name = "dev-redshift-namespace-role"
}

data "aws_iam_role" "redshift_prod" {
  # Created by infra/redshift/modules/redshift-serverless/iam.tf
  name = "prod-redshift-namespace-role"
}
