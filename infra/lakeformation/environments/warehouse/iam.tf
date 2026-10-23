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

data "aws_iam_role" "redshift_dev" {
  # Created by infra/redshift/modules/redshift-serverless/iam.tf
  name = "dev-redshift-namespace-role"
}

data "aws_iam_role" "redshift_prod" {
  # Created by infra/redshift/modules/redshift-serverless/iam.tf
  name = "prod-redshift-namespace-role"
}

data "aws_iam_role" "orcanexus_dev" {
  # Created by infra/aurora/environments/dev//modules/analytics.tf
  name = "orcanexus-dev-aurora-analytics-role"
}

# FIXME - uncomment when we have prod orcanexus ready
# data "aws_iam_role" "orcanexus_prod" {
#   # Created by infra/aurora/environments/prod//modules/analytics.tf
#   name = "orcanexus-prod-aurora-analytics-role"
# }
