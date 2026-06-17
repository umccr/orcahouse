data "aws_region" "current" {}

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
  for_each = toset(var.consumer_account_ids)

  principal          = each.value
  resource_share_arn = aws_ram_resource_share.lakeformation_share.arn
}

# -------------------------------------------------------
# Glue — One resource share for all consumer accounts
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
          AWS     = [for id in var.consumer_account_ids : "arn:aws:iam::${id}:root"]
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
  for_each = toset(var.consumer_account_ids)

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
resource "aws_lakeformation_permissions" "table_grant" {
  for_each = {
    for item in flatten([
      for account_id in var.consumer_account_ids : [
        for table_name, table_config in var.tables : {
          key        = "${account_id}__${table_name}"
          account_id = account_id
          table_name = table_name
          config     = table_config
        }
      ]
    ]) : item.key => item
  }

  principal                     = each.value.account_id
  permissions                   = ["SELECT", "DESCRIBE"]
  permissions_with_grant_option = ["SELECT", "DESCRIBE"]

  # No column restrictions — full table grant
  dynamic "table" {
    for_each = (
      length(each.value.config.included_columns) == 0 &&
      length(each.value.config.excluded_columns) == 0
    ) ? [1] : []

    content {
      database_name = var.database_name
      name          = each.value.table_name
      catalog_id    = var.dw_account_id
    }
  }

  # Included columns — whitelist
  dynamic "table_with_columns" {
    for_each = length(each.value.config.included_columns) > 0 ? [1] : []

    content {
      database_name = var.database_name
      name          = each.value.table_name
      catalog_id    = var.dw_account_id
      column_names  = each.value.config.included_columns
    }
  }

  # Excluded columns — blacklist
  dynamic "table_with_columns" {
    for_each = (
      length(each.value.config.included_columns) == 0 &&
      length(each.value.config.excluded_columns) > 0
    ) ? [1] : []

    content {
      database_name = var.database_name
      name          = each.value.table_name
      catalog_id    = var.dw_account_id

      column_wildcard {
        excluded_column_names = each.value.config.excluded_columns
      }
    }
  }

  depends_on = [
    aws_ram_principal_association.consumer_accounts
  ]
}

# -------------------------------------------------------
# Lake Formation — Data Cell Filters
# Created once, shared to all consumer accounts
# -------------------------------------------------------
# TODO complete the implementation for data cells filter - need a use case
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

    # Specific columns
    column_names = length(each.value.config.included_columns) > 0 ? each.value.config.included_columns : null

    # All columns — explicitly set excluded_column_names to empty list
    dynamic "column_wildcard" {
      for_each = length(each.value.config.included_columns) == 0 ? [1] : []
      content {
        excluded_column_names = []
      }
    }
  }
}
