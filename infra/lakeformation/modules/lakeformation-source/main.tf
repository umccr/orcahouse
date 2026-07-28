data "aws_region" "current" {}

locals {
  consumer_account_ids = keys(var.consumer_accounts)
  consumer_principal_arns = flatten([
    for account_id, account_config in var.consumer_accounts : account_config.principal_arns
  ])
}

# -------------------------------------------------------
# RAM — One resource share for all consumer accounts
# -------------------------------------------------------
resource "aws_ram_resource_share" "lakeformation_share" {
  name                      = "lakeformation-${var.database_name}-share"
  allow_external_principals = true

  tags = {
    Purpose = "LakeFormation Cross-Account Share"
  }
}

resource "aws_ram_resource_association" "glue_database" {
  resource_arn       = "arn:aws:glue:${data.aws_region.current.region}:${var.dw_account_id}:database/${var.database_name}"
  resource_share_arn = aws_ram_resource_share.lakeformation_share.arn
}

resource "aws_ram_principal_association" "consumer_accounts" {
  for_each = toset(local.consumer_account_ids)

  principal          = each.value
  resource_share_arn = aws_ram_resource_share.lakeformation_share.arn
}

# -------------------------------------------------------
# Glue — Resource policy for cross account access
# -------------------------------------------------------
resource "aws_glue_resource_policy" "cross_account" {
  enable_hybrid = "TRUE"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ram.amazonaws.com",
          AWS     = [for id in local.consumer_account_ids : "arn:aws:iam::${id}:root"]
        }
        Action = [
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:ShareResource"
        ]
        Resource = [
          "arn:aws:glue:${data.aws_region.current.region}:${var.dw_account_id}:catalog",
          "arn:aws:glue:${data.aws_region.current.region}:${var.dw_account_id}:database/${var.database_name}",
          "arn:aws:glue:${data.aws_region.current.region}:${var.dw_account_id}:table/${var.database_name}/*"
        ]
      }
    ]
  })
}

# -------------------------------------------------------
# Lake Formation — Database grant per consumer account
# -------------------------------------------------------
resource "aws_lakeformation_permissions" "database_grant" {
  for_each = toset(local.consumer_account_ids)

  principal                     = each.value
  permissions                   = ["DESCRIBE"]
  permissions_with_grant_option = ["DESCRIBE"]

  database {
    name       = var.database_name
    catalog_id = var.dw_account_id
  }

  depends_on = [
    aws_ram_principal_association.consumer_accounts
  ]
}

# -------------------------------------------------------
# Lake Formation — Table grants per consumer account
# -------------------------------------------------------
# FIXME table_grant Vs data_filter_grant
#  This is the key insight — data cells filters and broad table grants cannot coexist if you want the filter
#  restrictions to be enforced. The filter only takes effect when it is the only grant on that table for that principal.
#  Also revoke "IAMAllowedPrincipals" Group principal type with "All" permissions because this broad permission scope
#  always take precedent.
# resource "aws_lakeformation_permissions" "table_grant" {
#   for_each = {
#     for item in flatten([
#       for account_id in var.consumer_account_ids : [
#         for table_name in keys(var.tables) : {
#           key        = "${account_id}__${table_name}"
#           account_id = account_id
#           table_name = table_name
#         }
#       ]
#     ]) : item.key => item
#   }
#
#   principal                     = each.value.account_id
#   permissions                   = ["SELECT", "DESCRIBE"]
#   permissions_with_grant_option = ["SELECT", "DESCRIBE"]
#
#   table {
#     database_name = var.database_name
#     name          = each.value.table_name
#     catalog_id    = var.dw_account_id
#   }
#
#   depends_on = [
#     aws_ram_principal_association.consumer_accounts
#   ]
# }

# -------------------------------------------------------
# Lake Formation — Grant Data Cell Filters to Principal ARNs
# Granted directly to SSO role ARNs — not account ID
# -------------------------------------------------------
resource "aws_lakeformation_permissions" "data_filter_grant" {
  for_each = {
    for item in flatten([
      for principal_arn in local.consumer_principal_arns : [
        for filter_key, filter in aws_lakeformation_data_cells_filter.filters : {
          key           = "${principal_arn}__${filter_key}"
          principal_arn = principal_arn
          table_name    = filter.table_data[0].table_name
          filter_name   = filter.table_data[0].name
        }
      ]
    ]) : item.key => item
  }

  principal   = each.value.principal_arn
  permissions = ["SELECT"]

  data_cells_filter {
    database_name    = var.database_name
    table_name       = each.value.table_name
    name             = each.value.filter_name
    table_catalog_id = var.dw_account_id
  }

  depends_on = [
    aws_lakeformation_data_cells_filter.filters
  ]

  # FIXME WORKAROUND: Prevents the provider from timing out on cross-account list-permissions checks
  #  https://github.com/hashicorp/terraform-provider-aws/issues/48360
  #  https://github.com/hashicorp/terraform-provider-aws/issues/46951
  #  Error: reading Lake Formation permissions: timeout while waiting for state to become 'AVAILABLE' (timeout: 1m0s):
  #  listing permissions: operation error LakeFormation: ListPermissions, context deadline exceeded
  # lifecycle {
  #   ignore_changes = [
  #     data_cells_filter
  #   ]
  # }
}

# -------------------------------------------------------
# Lake Formation — Data Cell Filters
# Created once, shared to all consumer accounts
# -------------------------------------------------------
resource "aws_lakeformation_data_cells_filter" "filters" {
  for_each = {
    for item in flatten([
      for table_name, table_config in var.tables : [
        for filter_name, filter_config in table_config.data_filters : {
          key         = "${table_name}__${filter_name}"
          table_name  = table_name
          filter_name = filter_name
          config      = filter_config
        }
      ]
    ]) : item.key => item
  }

  table_data {
    database_name    = var.database_name
    table_name       = each.value.table_name
    name             = each.value.filter_name
    table_catalog_id = var.dw_account_id

    row_filter {
      dynamic "all_rows_wildcard" {
        for_each = each.value.config.row_filter_expression == null ? [1] : []
        content {}
      }

      filter_expression = each.value.config.row_filter_expression != null ? each.value.config.row_filter_expression : null
    }

    # Specific columns — inclusion
    column_names = length(each.value.config.included_columns) > 0 ? each.value.config.included_columns : null

    # All columns wildcard — with optional exclusion
    dynamic "column_wildcard" {
      for_each = length(each.value.config.included_columns) == 0 ? [1] : []
      content {
        excluded_column_names = length(each.value.config.excluded_columns) > 0 ? each.value.config.excluded_columns : []
      }
    }
  }
}

# In hybrid mode, the consumer (e.g. umccr-prod) SSO role needs both Lake Formation permissions (which we have set up)
# and IAM S3 read permissions on the DW account's S3 bucket. If not, this is the likely cause of the S3 403 when
# querying via Athena.
#
# Alternatively, you can disable hybrid mode on the S3 location registration — set HybridAccessEnabled: false — and
# Lake Formation handles S3 access entirely without needing a bucket policy.
#
# Verify S3 location is registered as AWS Lake Formation > Administration > Data lake locations
#   `aws lakeformation list-resources`
#
# For the same account (DW account), we also need to register the S3 bucket at
#   AWS Lake Formation > Permissions > Data locations
#
resource "aws_s3_bucket_policy" "cross_account_read" {
  for_each = toset(var.data_bucket_names)

  bucket = each.value

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = [for id in local.consumer_account_ids : "arn:aws:iam::${id}:root"]
        }
        Action = [
          "s3:GetObject"
        ]
        Resource = [
          "arn:aws:s3:::${each.value}",
          "arn:aws:s3:::${each.value}/*"
        ]
      }
    ]
  })
}
