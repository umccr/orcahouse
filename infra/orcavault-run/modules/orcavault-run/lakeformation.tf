# The Lake Formation grants for the dbt task role.

resource "aws_lakeformation_permissions" "cdc_database" {
  for_each  = toset(var.glue_databases)
  principal = aws_iam_role.dbt_task.arn

  database {
    name = each.key
  }
  permissions = ["DESCRIBE"]
}

resource "aws_lakeformation_permissions" "cdc_tables" {
  for_each  = toset(var.glue_databases)
  principal = aws_iam_role.dbt_task.arn

  table {
    database_name = each.key
    wildcard      = true
  }
  permissions = ["SELECT", "DESCRIBE"]
}
