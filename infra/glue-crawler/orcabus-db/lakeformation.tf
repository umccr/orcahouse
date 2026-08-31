resource "aws_lakeformation_permissions" "crawler_database" {
  for_each  = toset(local.databases)
  principal = aws_iam_role.glue_crawler.arn

  database {
    name = "orcabus_${each.key}"
  }
  permissions = ["DESCRIBE", "CREATE_TABLE"]
}

resource "aws_lakeformation_permissions" "crawler_tables" {
  for_each  = toset(local.databases)
  principal = aws_iam_role.glue_crawler.arn

  table {
    database_name = "orcabus_${each.key}"
    wildcard      = true
  }
  permissions = ["SELECT", "ALTER", "DROP"]
}
