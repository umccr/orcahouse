# The following TF resources configure Lake Formation for cross-account permissions for sharing (via RAM see ram.tf).
#
# Login to Warehouse account and navigate to
# Console > AWS Lake Formation > Data permissions

# ==========================================
# DATABASE GRANTS TO CONSUMER ACCOUNTS
# ==========================================
resource "aws_lakeformation_permissions" "cross_account_database" {
  for_each = {
    for item in flatten([
      for account_id in local.consumer_account_ids : [
        for db in local.shared_databases : {
          key        = "${account_id}__${db}"
          account_id = account_id
          database   = db
        }
      ]
    ]) : item.key => item
  }

  principal                     = each.value.account_id
  permissions                   = ["DESCRIBE"]
  permissions_with_grant_option = ["DESCRIBE"]

  database {
    name       = each.value.database
    catalog_id = local.account_id
  }

  depends_on = [
    aws_ram_principal_association.consumer_accounts
  ]
}

# ==========================================
# TABLE GRANTS TO CONSUMER ACCOUNTS
# ==========================================
resource "aws_lakeformation_permissions" "cross_account_tables" {
  for_each = {
    for item in flatten([
      for account_id in local.consumer_account_ids : [
        for db in local.shared_databases : {
          key        = "${account_id}__${db}"
          account_id = account_id
          database   = db
        }
      ]
    ]) : item.key => item
  }

  principal                     = each.value.account_id
  permissions                   = ["SELECT", "DESCRIBE"]
  permissions_with_grant_option = ["SELECT", "DESCRIBE"]

  table {
    database_name = each.value.database
    catalog_id    = local.account_id
    wildcard      = true
  }

  depends_on = [
    aws_ram_principal_association.consumer_accounts
  ]
}
