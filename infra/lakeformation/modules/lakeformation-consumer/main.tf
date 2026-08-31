# Login to consumer account and navigate to
# Console > AWS Glue > Data Catalog > Databases

resource "aws_glue_catalog_database" "resource_links" {
  for_each = var.database_resource_links

  name = each.key

  target_database {
    catalog_id    = var.dw_account_id
    database_name = each.value
  }
}
