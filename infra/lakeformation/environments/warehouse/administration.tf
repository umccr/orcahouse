# Login to Warehouse account and navigate to
# Console > AWS Lake Formation > Administration

resource "aws_lakeformation_data_lake_settings" "warehouse_settings" {
  # Define Data Lake Administrators
  admins = flatten([
    tolist(data.aws_iam_roles.warehouse_sso_admin.arns),
    tolist(data.aws_iam_roles.warehouse_sso_owner.arns)
  ])

  # Leaving the following settings out completely signals to the API to disable "Hybrid" mode defaults.
  # DO NOT include create_database_default_permissions {}
  # DO NOT include create_table_default_permissions {}

  # Why? ^^
  # It makes the LF setup switching to Lake Formation Only access mode.
  #
  # By default, when an account is created Lake Formation assigns every database and table to a special virtual group
  # called IAMAllowedPrincipal, which includes all "IAM principals" with any catalog-level IAM or AWS Glue policies
  # (basically "any" IAM role can access any catalog database/table by default). As long as this group has permissions
  # on a resource, every principal in your account can see or manage that resource — even if you later grant more
  # restricted Lake Formation policies.
  #
  # Removing the IAMAllowedPrincipal entry "locks down" the resource so that those databases and tables are only
  # accessible through the Lake Formation grants that apply.
  #
  # REF:
  # https://joudwawad.medium.com/data-engineering-on-aws-aws-lake-formation-for-data-governance-and-security-9c6e4d049350

  # We can further introduce LF-Tags - Tag-based Access Control (TBAC) for granular fine grain access.
  # https://aws.github.io/aws-lakeformation-best-practices/adopting-lake-formation/lake-formation-adoption-modes/
  # https://aws.github.io/aws-lakeformation-best-practices/lf-tags/basics/
}

# -------------------------------------------------------
# Lake Formation — Register S3 Data Lake Locations
# Console > AWS Lake Formation > Administration > Data lake locations
# -------------------------------------------------------
locals {
  data_lake_s3_locations = [
    "oncovault-dev-warehouse-115253169271-ap-southeast-2-an/v1/tables/oncovault_dev_mart",
    "orcavault-dev-warehouse-115253169271-ap-southeast-2-an/v1/parquet/mart"
  ]
}

resource "aws_lakeformation_resource" "s3_locations" {
  for_each = toset(local.data_lake_s3_locations)

  arn                     = "arn:aws:s3:::${each.value}"
  use_service_linked_role = true
}
