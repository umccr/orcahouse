# --- Lake Formation grants for the dbt task role.
#
# The account uses Lake Formation only mode, so IAM alone doesn't let a role
# see a Glue database. These grant the task role read on the CDC databases it
# queries through awsdatacatalog, like the grants infra/glue-crawler/orcabus-db
# makes for its crawler role. Applying this needs a Lake Formation admin.

resource "aws_lakeformation_permissions" "cdc_database" {
  for_each  = toset(var.cdc_glue_databases)
  principal = aws_iam_role.dbt_task.arn

  database {
    name = each.key
  }
  permissions = ["DESCRIBE"]
}

resource "aws_lakeformation_permissions" "cdc_tables" {
  for_each  = toset(var.cdc_glue_databases)
  principal = aws_iam_role.dbt_task.arn

  table {
    database_name = each.key
    wildcard      = true
  }
  permissions = ["SELECT", "DESCRIBE"]
}
