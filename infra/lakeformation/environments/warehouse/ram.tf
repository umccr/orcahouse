# Concept:
# The key component (AWS Resource Access Manager - RAM) that underpins sharing resources between AWS accounts.
# The shared resources (i.e. Glue Catalog databases) "sharing access conditions" are governed by LakeFormation.
# (see permissions_cross_accounts.tf)
#
# Login to Warehouse account and navigate to
# Console > AWS RAM > Shared by me

locals {
  consumer_account_ids = [
    "472057503814",  # umccr-prod
  ]

  shared_databases = [
    "oncovault_dev_mart",
    "orcavault_dev_mart",
  ]
}

resource "aws_ram_resource_share" "lakeformation_share" {
  name                      = "lakeformation-warehouse-share"
  allow_external_principals = true

  tags = {
    Purpose = "LakeFormation Cross-Account Share"
  }
}

resource "aws_ram_principal_association" "consumer_accounts" {
  for_each = toset(local.consumer_account_ids)

  principal          = each.value
  resource_share_arn = aws_ram_resource_share.lakeformation_share.arn
}

resource "aws_ram_resource_association" "glue_databases" {
  for_each = toset(local.shared_databases)

  resource_arn       = "arn:aws:glue:ap-southeast-2:${data.aws_caller_identity.current.id}:database/${each.value}"
  resource_share_arn = aws_ram_resource_share.lakeformation_share.arn
}
