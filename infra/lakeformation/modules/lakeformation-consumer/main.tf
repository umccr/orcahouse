# -------------------------------------------------------
# Glue — Resource Link for the Shared Database
# -------------------------------------------------------
resource "aws_glue_catalog_database" "resource_link" {
  name = var.this_account_database_name

  target_database {
    catalog_id    = var.dw_account_id
    database_name = var.dw_database_name
  }
}

# -------------------------------------------------------
# Lake Formation — Grant DESCRIBE on Resource Link Database
# Every principal needs this to see the database locally
# -------------------------------------------------------
resource "aws_lakeformation_permissions" "resource_link_grant" {
  for_each = var.principal_grants

  principal   = each.key
  permissions = ["DESCRIBE"]

  database {
    name       = aws_glue_catalog_database.resource_link.name
    catalog_id = var.this_account_id
  }

  depends_on = [
    aws_glue_catalog_database.resource_link,
  ]
}

# -------------------------------------------------------
# Lake Formation — Table Grants to Local Principals
# For principals accessing full tables (no row filter)
# -------------------------------------------------------
resource "aws_lakeformation_permissions" "table_grant" {
  for_each = {
    for item in flatten([
      for role_arn, role_config in var.principal_grants : [
        for table_name in role_config.tables : {
          key         = "${role_arn}__${table_name}"
          role_arn    = role_arn
          table_name  = table_name
          permissions = role_config.permissions
        }
      ]
    ]) : item.key => item
  }

  principal   = each.value.role_arn
  permissions = each.value.permissions

  table_with_columns {
    name          = each.value.table_name
    catalog_id    = var.dw_account_id
    database_name = var.dw_database_name
    wildcard      = true
  }

  depends_on = [
    aws_glue_catalog_database.resource_link,
  ]
}

# ---

# -------------------------------------------------------
# Glue — Resource Link for each Shared Table
# Without this, tables are not visible in consumer account
# -------------------------------------------------------
# resource "aws_glue_catalog_table" "table_resource_link" {
#   for_each      = var.tables
#   name          = each.key
#   database_name = aws_glue_catalog_database.resource_link.name
#
#   target_table {
#     catalog_id    = var.dw_account_id
#     database_name = var.dw_database_name
#     name          = each.key
#   }
#
#   depends_on = [
#     aws_glue_catalog_database.resource_link
#   ]
# }

# -------------------------------------------------------
# Lake Formation — Grant DESCRIBE on each Table Resource Link
# Principals need this to see the tables locally
# -------------------------------------------------------
# resource "aws_lakeformation_permissions" "table_resource_link_grant" {
#   for_each = {
#     for item in flatten([
#       for role_arn, role_config in var.principal_grants : [
#         for table_name in keys(var.tables) : {
#           key        = "${role_arn}__${table_name}"
#           role_arn   = role_arn
#           table_name = table_name
#         }
#       ]
#     ]) : item.key => item
#   }
#
#   principal   = each.value.role_arn
#   permissions = ["DESCRIBE"]
#
#   table {
#     database_name = aws_glue_catalog_database.resource_link.name
#     name          = each.value.table_name
#     catalog_id    = var.this_account_id
#   }
#
#   depends_on = [
#     aws_glue_catalog_database.resource_link,
#     aws_glue_catalog_table.table_resource_link,
#     # aws_lakeformation_data_lake_settings.consumer
#   ]
# }
